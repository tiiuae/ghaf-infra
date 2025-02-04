# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  self,
  lib,
  inputs,
  ...
}:
let
  # whenever a build is done, upload it to the blob storage via http (going
  # through the rclone proxy).
  # The secret-key= URL parameter configures the store, and which signing key it
  # should use while uploading, but neither the key nor its location is sent
  # over HTTP.
  post-build-hook =
    pkgs.writeScript "upload" # bash
      ''
        set -eu
        set -f # disable globbing
        export IFS=' '

        echo "Uploading paths" $OUT_PATHS

        # Retry upload three times if it fails. If it fails third time then exit with error.
        # This should fix the upload race condition.
        ERR=1
        for i in {1..3}; do
          nix --extra-experimental-features nix-command copy --to 'http://localhost:8080?secret-key=/etc/secrets/nix-signing-key&compression=zstd' $OUT_PATHS &&
            ERR=0 && break ||
            [ $i -le 3 ] && echo "Retrying in 10 seconds; attempt=$i failed..." && sleep 10
        done
        exit $ERR
      '';

  jenkins-casc = ./jenkins-casc.yaml;

  get-secret =
    pkgs.writers.writePython3 "get-secret"
      {
        libraries = with pkgs.python3.pkgs; [
          azure-keyvault-secrets
          azure-identity
        ];
      }
      ''
        """
        This script retrieves a secret specified in $SECRET_NAME
        from an Azure Key Vault in $KEY_VAULT_NAME
        and prints it to stdout.

        It uses the default Azure credential client.
        """

        from azure.keyvault.secrets import SecretClient
        from azure.identity import DefaultAzureCredential

        import os

        key_vault_name = os.environ["KEY_VAULT_NAME"]
        secret_name = os.environ["SECRET_NAME"]

        credential = DefaultAzureCredential()
        client = SecretClient(
            vault_url=f"https://{key_vault_name}.vault.azure.net",
            credential=credential
        )

        s = client.get_secret(secret_name)
        print(s.value)
      '';

  # nixos 24.05 pkgs is used for rclone
  old-pkgs = import inputs.nixpkgs-24-05 { inherit (pkgs) system; };

  # rclone 1.68.2 breaks our pipelines, keep using the old 1.66 version
  rclone = old-pkgs.callPackage ../../../pkgs/rclone { };
in
{
  imports = [
    ../../azure-common.nix
    self.nixosModules.service-openssh
    self.nixosModules.service-rclone-http
  ];

  # Configure /var/lib/jenkins in /etc/fstab.
  # Due to an implicit RequiresMountsFor=$state-dir, systemd
  # will block starting the service until this mounted.
  fileSystems."/var/lib/jenkins" = {
    device = "/dev/disk/azure/scsi1/lun10";
    fsType = "ext4";
    options = [
      "x-systemd.makefs"
      "x-systemd.growfs"
    ];
  };

  # Configure /var/lib/caddy in /etc/fstab.
  # Due to an implicit RequiresMountsFor=$state-dir, systemd
  # will block starting the service until this mounted.
  fileSystems."/var/lib/caddy" = {
    device = "/dev/disk/azure/scsi1/lun11";
    fsType = "ext4";
    options = [
      "x-systemd.makefs"
      "x-systemd.growfs"
    ];
  };

  services.jenkins = {
    enable = true;
    listenAddress = "localhost";
    port = 8081;
    withCLI = true;
    packages =
      with pkgs;
      [
        bashInteractive # 'sh' step in jenkins pipeline requires this
        coreutils
        nix
        git
        zstd
        jq
        csvkit
        curl
        nix-eval-jobs
      ]
      ++ [
        rclone # used to copy artifacts
        inputs.sbomnix.packages.${pkgs.system}.sbomnix # sbomnix, provenance, vulnxscan
        inputs.ci-yubi.packages.${pkgs.system}.sigver # signing scripts
      ];

    extraJavaOptions = [
      # Useful when the 'sh' step fails:
      "-Dorg.jenkinsci.plugins.durabletask.BourneShellScript.LAUNCH_DIAGNOSTICS=true"
      # If we want to allow robot framework reports, we need to adjust Jenkins CSP:
      # https://plugins.jenkins.io/robot/#plugin-content-log-file-not-showing-properly
      "-Dhudson.model.DirectoryBrowserSupport.CSP=\"sandbox allow-scripts; default-src 'none'; img-src 'self' data: ; style-src 'self' 'unsafe-inline' data: ; script-src 'self' 'unsafe-inline' 'unsafe-eval';\""
      # Point to configuration-as-code config
      "-Dcasc.jenkins.config=${jenkins-casc}"
      # Increase the number of rows shown in Stage View (default is 10)
      "-Dcom.cloudbees.workflow.rest.external.JobExt.maxRunsPerJob=32"
    ];

    plugins = import ./plugins.nix { inherit (pkgs) stdenv fetchurl; };

    # Configure jenkins job(s):
    # https://jenkins-job-builder.readthedocs.io/en/latest/project_pipeline.html
    # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/continuous-integration/jenkins/job-builder.nix
    jobBuilder = {
      enable = true;
      nixJobs =
        lib.mapAttrsToList
          (display-name: script: {
            job = {
              inherit display-name;
              name = script;
              project-type = "pipeline";
              concurrent = true;
              pipeline-scm = {
                script-path = "${script}.groovy";
                lightweight-checkout = true;
                scm = [
                  {
                    git = {
                      url = "https://github.com/tiiuae/ghaf-jenkins-pipeline.git";
                      clean = true;
                      branches = [ "*/main" ];
                    };
                  }
                ];
              };
            };
          })
          {
            "Ghaf main pipeline" = "ghaf-main-pipeline";
            "Ghaf pre-merge pipeline" = "ghaf-pre-merge-pipeline";
            "Ghaf nightly pipeline" = "ghaf-nightly-pipeline";
            "Ghaf release pipeline" = "ghaf-release-pipeline";
            "Ghaf performance tests" = "ghaf-perftest-pipeline";
            "Ghaf HW test" = "ghaf-hw-test";
            "Ghaf parallel HW test" = "ghaf-parallel-hw-test";
            "FMO OS main pipeline" = "fmo-os-main-pipeline";
          };
    };
  };

  systemd.services.jenkins.serviceConfig = {
    Restart = "on-failure";
  };

  systemd.services.jenkins-job-builder.serviceConfig = {
    Restart = "on-failure";
    RestartSec = 5;
  };

  # set StateDirectory=jenkins, so state volume has the right permissions
  # and we wait on the mountpoint to appear.
  # https://github.com/NixOS/nixpkgs/pull/272679
  systemd.services.jenkins.serviceConfig.StateDirectory = "jenkins";

  # Install jenkins plugins, apply initial jenkins config
  systemd.services.jenkins-config = {
    after = [ "jenkins-job-builder.service" ];
    wantedBy = [ "multi-user.target" ];
    # Make `jenkins-cli` available
    path = with pkgs; [ jenkins ];
    # Implicit URL parameter for `jenkins-cli`
    environment = {
      JENKINS_URL = "http://localhost:8081";
    };
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 5;
      RequiresMountsFor = "/var/lib/jenkins";
    };
    script =
      let
        jenkins-auth = "-auth admin:\"$(cat /var/lib/jenkins/secrets/initialAdminPassword)\"";

        # disable initial setup, which needs to happen *after* all jenkins-cli setup.
        # otherwise we won't have initialAdminPassword.
        # Disabling the setup wizard cannot happen from configuration-as-code either.
        jenkins-groovy = pkgs.writeText "groovy" ''
          #!groovy

          import jenkins.model.*
          import hudson.util.*;
          import jenkins.install.*;

          def instance = Jenkins.getInstance()

          instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
          instance.save()
        '';
      in
      ''
        # Disable initial install
        jenkins-cli ${jenkins-auth} groovy = < ${jenkins-groovy}

        # Restart jenkins
        jenkins-cli ${jenkins-auth} safe-restart
      '';
  };

  # Define a fetch-remote-build-ssh-key unit populating
  # /etc/secrets/remote-build-ssh-key from Azure Key Vault.
  # Make it before and requiredBy nix-daemon.service.
  systemd.services.fetch-build-ssh-key = {
    after = [ "network.target" ];
    before = [ "nix-daemon.service" ];
    requires = [ "network.target" ];
    wantedBy = [
      # nix-daemon is socket-activated, and having it here should be sufficient
      # to fetch the keys whenever a jenkins job connects to the daemon first.
      # This means this service will effectively get socket-activated on the
      # first nix-daemon connection.
      "nix-daemon.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      EnvironmentFile = "/var/lib/fetch-build-ssh-key/env";
      Restart = "on-failure";
    };
    script = ''
      umask 077
      mkdir -p /etc/secrets/
      ${get-secret} > /etc/secrets/remote-build-ssh-key
    '';
  };

  # populate-known-hosts populates /root/.ssh/known_hosts with all hosts in the
  # builder subnet.
  systemd.services.populate-known-hosts = {
    after = [ "network.target" ];
    before = [ "nix-daemon.service" ];
    requires = [ "network.target" ];
    wantedBy = [
      # nix-daemon is socket-activated, and having it here should be sufficient
      # to fetch the keys whenever a jenkins job connects to the daemon first.
      # This means this service will effectively get socket-activated on the
      # first nix-daemon connection.
      "nix-daemon.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
    };
    script = ''
      umask 077
      mkdir -p /root/.ssh
      ${pkgs.openssh}/bin/ssh-keyscan -f /var/lib/builder-keyscan/scanlist -v -t ed25519 > /root/.ssh/known_hosts
    '';
  };

  # Define a fetch-binary-cache-signing-key unit populating
  # /etc/secrets/nix-signing-key from Azure Key Vault.
  # Make it before and requiredBy nix-daemon.service.
  systemd.services.fetch-binary-cache-signing-key = {
    after = [ "network.target" ];
    before = [ "nix-daemon.service" ];
    requires = [ "network.target" ];
    wantedBy = [
      # nix-daemon is socket-activated, and having it here should be sufficient
      # to fetch the keys whenever a jenkins job connects to the daemon first.
      # This means this service will effectively get socket-activated on the
      # first nix-daemon connection.
      "nix-daemon.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      EnvironmentFile = "/var/lib/fetch-binary-cache-signing-key/env";
      Restart = "on-failure";
    };
    script = ''
      umask 077
      mkdir -p /etc/secrets/
      ${get-secret} > /etc/secrets/nix-signing-key
    '';
  };

  # Provide a webdav endpoint for Jenkins to upload artifacts to.
  systemd.services.rclone-jenkins-artifacts = {
    after = [ "network.target" ];
    serviceConfig = {
      Type = "notify";
      Restart = "always";
      RestartSec = 2;
      DynamicUser = true;
      RuntimeDirectory = "rclone-http";
      EnvironmentFile = "/var/lib/rclone-jenkins-artifacts/env";
      ExecStart = lib.concatStringsSep " " [
        "${rclone}/bin/rclone"
        "serve"
        "webdav"
        "--dir-cache-time"
        "5s"
        "--azureblob-env-auth"
        "--disable-dir-list"
        ":azureblob:jenkins-artifacts-v1"
      ];
    };
  };
  # Restrict connections to the jenkins user only.
  systemd.sockets.rclone-jenkins-artifacts = {
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "/run/rclone-jenkins-artifacts.sock";
      SocketUser = "jenkins";
      SocketMode = "0600";
    };
  };

  # Provide a (read-only) HTTP endpoint (with listing) to browse artifacts.
  # These are exposed through caddy.
  systemd.services.rclone-jenkins-artifacts-browse = {
    after = [ "network.target" ];
    serviceConfig = {
      Type = "notify";
      Restart = "always";
      RestartSec = 2;
      DynamicUser = true;
      RuntimeDirectory = "rclone-http";
      EnvironmentFile = "/var/lib/rclone-jenkins-artifacts/env";
      ExecStart = lib.concatStringsSep " " [
        "${rclone}/bin/rclone"
        "serve"
        "http"
        "--read-only"
        "--dir-cache-time"
        "5s"
        "--azureblob-env-auth"
        ":azureblob:jenkins-artifacts-v1"
      ];
    };
  };
  systemd.sockets.rclone-jenkins-artifacts-browse = {
    wantedBy = [ "sockets.target" ];
    socketConfig.ListenStream = "/run/rclone-jenkins-artifacts-browse.sock";
  };

  # Enable early out-of-memory killing.
  # Make nix builds more likely to be killed over more important services.
  services.earlyoom = {
    enable = true;
    # earlyoom sends SIGTERM once below 5% and SIGKILL when below half
    # of freeMemThreshold
    freeMemThreshold = 5;
    extraArgs = [
      "--prefer '^(nix-daemon)$'"
      "--avoid '^(java|jenkins-.*|sshd|systemd|systemd-.*)$'"
    ];
  };

  # Tell the Nix evaluator to garbage collect more aggressively
  environment.variables.GC_INITIAL_HEAP_SIZE = "1M";
  # Always overcommit: pretend there is always enough memory
  # until it actually runs out
  boot.kernel.sysctl."vm.overcommit_memory" = "1";

  nix.extraOptions = ''
    builders-use-substitutes = true
    builders = @/etc/nix/machines
    # Build remote by default
    max-jobs = 0
    post-build-hook = ${post-build-hook}
  '';

  services.rclone-http = {
    enable = true;
    listenAddress = "[::1]:8080";
    protocol = "webdav";
    extraArgs = [
      "--azureblob-env-auth"
      "--disable-dir-list"
    ];
    remote = ":azureblob:binary-cache-v1";
  };

  services.caddy = {
    enable = true;
    enableReload = false;
    configFile = pkgs.writeText "Caddyfile" ''
      # Disable the admin API, we don't want to reconfigure Caddy at runtime.
      {
        admin off
      }

      https://{$SITE_ADDRESS} {
        # Route /artifacts requests to rclone-jenkins-artifacts-browse,
        # stripping `/artifacts` from the path.
        handle_path /artifacts/* {
          reverse_proxy unix//run/rclone-jenkins-artifacts-browse.sock
        }
        # Proxy all other requests to jenkins as-is.
        handle {
          reverse_proxy localhost:8081
        }
      }
    '';
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile = "/var/lib/caddy/caddy.env";

  # Configure Nix to use the bucket (through rclone-http) as a substitutor.
  # The public key is passed in externally.
  nix.settings.substituters = [ "http://localhost:8080" ];

  # Wait for cloud-init mounting before we start caddy.
  systemd.services.caddy.after = [ "cloud-init.service" ];
  systemd.services.caddy.requires = [ "cloud-init.service" ];

  # Expose the HTTP[S] port. We still need HTTP for the HTTP-01 challenge.
  # While TLS-ALPN-01 could be used, disabling HTTP-01 seems only possible from
  # the JSON config, which won't work alongside Caddyfile.
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  system.stateVersion = "23.05";
}
