# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  self,
  lib,
  ...
}: let
  # whenever a build is done, upload it to the blob storage via http (going
  # through the rclone proxy).
  # The secret-key= URL parameter configures the store, and which signing key it
  # should use while uploading, but neither the key nor its location is sent
  # over HTTP.
  post-build-hook = pkgs.writeScript "upload" ''
    set -eu
    set -f # disable globbing
    export IFS=' '

    echo "Uploading paths" $OUT_PATHS
    exec nix --extra-experimental-features nix-command copy --to 'http://localhost:8080?secret-key=/etc/secrets/nix-signing-key&compression=zstd' $OUT_PATHS
  '';

  # TODO: sort out jenkins authentication e.g.:
  # https://plugins.jenkins.io/github-oauth/
  # Below config requires admin to trigger builds or manage jenkins
  # allowing read access for anonymous users:
  jenkins-groovy = pkgs.writeText "groovy" ''
    #!groovy

    import jenkins.model.*
    import jenkins.install.*
    import hudson.security.*

    def instance = Jenkins.getInstance()
    // Disable Setup Wizard
    instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)

    // Allow anonymous read access
    def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
    strategy.setAllowAnonymousRead(true)
    instance.setAuthorizationStrategy(strategy)
    instance.save()
  '';

  get-secret =
    pkgs.writers.writePython3 "get-secret" {
      libraries = with pkgs.python3.pkgs; [azure-keyvault-secrets azure-identity];
    } ''
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
in {
  imports = [
    ../../azure-common.nix
    self.nixosModules.service-openssh
    self.nixosModules.service-rclone-http
  ];

  # Configure /var/lib/jenkins in /etc/fstab.
  # Due to an implicit RequiresMountsFor=$state-dir, systemd
  # will block starting the service until this mounted.
  fileSystems."/var/lib/jenkins" = {
    device = "/dev/disk/by-lun/10";
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
    device = "/dev/disk/by-lun/11";
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
    packages = with pkgs; [
      bashInteractive # 'sh' step in jenkins pipeline requires this
      coreutils
      nix
      git
      zstd
    ];
    extraJavaOptions = [
      # Useful when the 'sh' step fails:
      "-Dorg.jenkinsci.plugins.durabletask.BourneShellScript.LAUNCH_DIAGNOSTICS=true"
    ];
    # Configure jenkins job(s):
    # https://jenkins-job-builder.readthedocs.io/en/latest/project_pipeline.html
    # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/continuous-integration/jenkins/job-builder.nix
    jobBuilder = {
      enable = true;
      nixJobs = [
        {
          job = {
            name = "ghaf-pipeline";
            project-type = "pipeline";
            pipeline-scm = {
              scm = [
                {
                  git = {
                    # TODO: eventually the Jenkins pipeline script should probably
                    # be part of Ghaf repo at: https://github.com/tiiuae/ghaf,
                    # but we are not ready for that yet. For now, we read the
                    # Jenkinsfile from the following repo:
                    url = "https://github.com/tiiuae/ghaf-jenkins-pipeline.git";
                    clean = true;
                    branches = ["*/main"];
                  };
                }
              ];
              script-path = "ghaf-build-pipeline.groovy";
              lightweight-checkout = true;
            };
          };
        }
      ];
    };
  };
  systemd.services.jenkins.serviceConfig = {Restart = "on-failure";};
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
    after = ["jenkins-job-builder.service"];
    wantedBy = ["multi-user.target"];
    # Make `jenkins-cli` available
    path = with pkgs; [jenkins];
    # Implicit URL parameter for `jenkins-cli`
    environment = {
      JENKINS_URL = "http://localhost:8081";
    };
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 5;
    };
    script = let
      jenkins-auth = "-auth admin:\"$(cat /var/lib/jenkins/secrets/initialAdminPassword)\"";
    in ''
      # Install plugins
      jenkins-cli ${jenkins-auth} install-plugin "workflow-aggregator" "github" "timestamper" "pipeline-stage-view" "blueocean" -deploy

      # Jenkins groovy config
      jenkins-cli ${jenkins-auth} groovy = < ${jenkins-groovy}

      # Restart jenkins
      jenkins-cli ${jenkins-auth} safe-restart
    '';
  };

  # Define a fetch-remote-build-ssh-key unit populating
  # /etc/secrets/remote-build-ssh-key from Azure Key Vault.
  # Make it before and requiredBy nix-daemon.service.
  systemd.services.fetch-build-ssh-key = {
    after = ["network.target"];
    before = ["nix-daemon.service"];
    requires = ["network.target"];
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
    after = ["network.target"];
    before = ["nix-daemon.service"];
    requires = ["network.target"];
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
    after = ["network.target"];
    before = ["nix-daemon.service"];
    requires = ["network.target"];
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
    protocol = "webdav";
    remote = ":azureblob:binary-cache-v1";
  };

  services.caddy = {
    enable = true;
    configFile = pkgs.writeText "Caddyfile" ''
      # Disable the admin API, we don't want to reconfigure Caddy at runtime.
      {
        admin off
      }

      # Proxy all requests to jenkins.
      https://{$SITE_ADDRESS} {
        reverse_proxy localhost:8081
      }
    '';
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile = "/var/lib/caddy/caddy.env";

  # Configure Nix to use the bucket (through rclone-http) as a substitutor.
  # The public key is passed in externally.
  nix.settings.substituters = [
    "http://localhost:8080"
  ];

  # Wait for cloud-init mounting before we start caddy.
  systemd.services.caddy.after = ["cloud-init.service"];
  systemd.services.caddy.requires = ["cloud-init.service"];

  # Expose the HTTPS port. No need for HTTP, as caddy can use TLS-ALPN-01.
  networking.firewall.allowedTCPPorts = [443];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  system.stateVersion = "23.05";
}
