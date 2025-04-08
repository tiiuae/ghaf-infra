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

  jenkins-casc = {
    appearance = {
      pipelineGraphView = {
        showGraphOnBuildPage = true;
      };
    };
    jenkins = {
      authorizationStrategy = {
        globalMatrix = {
          # TODO: more granular github teams needed
          entries = [
            {
              group = {
                name = "authenticated";
                permissions = [
                  "Agent/Build"
                  "Job/Build"
                  "Job/Cancel"
                  "Job/Configure"
                  "Job/Create"
                  "Job/Discover"
                  "Job/Move"
                  "Job/Read"
                  "Job/Workspace"
                  "Lockable Resources/Unlock"
                  "Lockable Resources/View"
                  "Metrics/View"
                  "Overall/Read"
                  "Run/Delete"
                  "Run/Replay"
                  "Run/Update"
                ];
              };
            }
            {
              group = {
                name = "tiiuae:devenv-fi";
                permissions = [
                  "Overall/Administer"
                ];
              };
            }
          ];
        };
      };
      markupFormatter = {
        rawHtml = {
          disableSyntaxHighlighting = false;
        };
      };

      numExecutors = 4;
      securityRealm = {
        reverseProxy = {
          customLogOutUrl = "/oauth2/sign_out";
          forwardedDisplayName = "X-Forwarded-DisplayName";
          forwardedEmail = "X-Forwarded-Mail";
          forwardedUser = "X-Forwarded-User";
          headerGroups = "X-Forwarded-Groups";
          headerGroupsDelimiter = ",";
          disableLdapEmailResolver = true;
          inhibitInferRootDN = false;
        };
      };

      nodes = # all permutations of device and set lists
        lib.mapCartesianProduct
          (
            { set, device }:
            {
              permanent = {
                name = "${set}-${device}";
                labelString = device;
                launcher = "inbound";
                mode = "EXCLUSIVE";
                remoteFS = "/var/lib/jenkins/agents/${device}";
                retentionStrategy = "always";
              };
            }
          )
          {
            set = [
              "dev"
              "prod"
              "release"
            ];
            device = [
              "lenovo-x1"
              "nuc"
              "orin-agx"
              "orin-nx"
              "riscv"
            ];
          };
    };

    unclassified = {
      location = {
        url = "\${file:/var/lib/jenkins-casc/url}";
      };
      lockableResourcesManager = {
        declaredResources = [
          {
            description = "Nix evaluator lock";
            name = "evaluator";
          }
          {
            description = "SBOM generation lock";
            name = "sbom";
          }
        ];
      };
      timestamper = {
        allPipelines = true;
      };
    };

    jobs =
      lib.mapAttrsToList
        (displayName: script: {
          script = ''
            pipelineJob('${script}') {
              definition {
                cpsScm {
                  scm {
                    git {
                      remote {
                        url('https://github.com/tiiuae/ghaf-jenkins-pipeline.git')
                      }
                      branch('*/main')
                    }
                  }
                  scriptPath('${script}.groovy')
                  lightweight()
                }
              }
              displayName('${displayName}')
            }'';
        })
        {
          "Ghaf main pipeline" = "ghaf-main-pipeline";
          "Ghaf pre-merge pipeline" = "ghaf-pre-merge-pipeline";
          "Ghaf nightly pipeline" = "ghaf-nightly-pipeline";
          "Ghaf release pipeline" = "ghaf-release-pipeline";
          "Ghaf performance tests" = "ghaf-perftest-pipeline";
          "Ghaf HW test" = "ghaf-hw-test";
        };
  };

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

  users.users = {
    testagent-dev = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDVZVd2ZBBHBYCJVOhjhfVXi4lrVYtcH5CkQjTqBfg/4 root@nixos"
      ];
    };
    testagent-prod = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "sh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILXYn8XEtZ/LoRBnM/GwNJMg0gcpFMEYEyQX3X9DTENx root@nixos"
      ];
    };
    testagent-release = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPP2xRl4jtu1ARpyj9W3uEo+GACLywosKhal432CgK+H mytarget"
      ];
    };
    testagent-uae-dev = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHO30maPQbVUqURaur8ze2S0vrrUivj2QdItIHsK75RS root@fayad-X1-testagent"
      ];
    };
  };

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
      # Disable the intitial setup wizard, and the creation of initialAdminPassword.
      "-Djenkins.install.runSetupWizard=false"
      # Point to configuration-as-code config
      "-Dcasc.jenkins.config=${builtins.toFile "jenkins-casc.yaml" (builtins.toJSON jenkins-casc)}"
      # Increase the number of rows shown in Stage View (default is 10)
      "-Dcom.cloudbees.workflow.rest.external.JobExt.maxRunsPerJob=32"
    ];

    plugins = import ./plugins.nix { inherit (pkgs) stdenv fetchurl; };
  };

  systemd.services.jenkins.serviceConfig = {
    Restart = "on-failure";
  };

  # set StateDirectory=jenkins, so state volume has the right permissions
  # and we wait on the mountpoint to appear.
  # https://github.com/NixOS/nixpkgs/pull/272679
  systemd.services.jenkins.serviceConfig.StateDirectory = "jenkins";

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
        
        # as recommended by jenkins, these paths should not require auth
        @unauthenticated {
          path /assets /assets/*
          path /avatar-cache /avatar-cache/*
          path /bitbucket-scmsource-hook /bitbucket-scmsource-hook/*
          path /blue /blue/*
          path /cascMergeStrategy /cascMergeStrategy/*
          path /cli /cli/*
          path /custom-avatar-cache /custom-avatar-cache/*
          path /git /git/*
          path /github-webhook /github-webhook/*
          path /instance-identity /instance-identity/*
          path /jnlpJars /jnlpJars/*
          path /jwt-auth /jwt-auth/*
          path /metrics /metrics/*
          path /reload-configuration-as-code /reload-configuration-as-code/*
          path /static-files /static-files/*
          path /subversion /subversion/*
          path /wsagents /wsagents/*
        }

        handle @unauthenticated {
          reverse_proxy localhost:8081
        }
        
        # Route /artifacts requests to rclone-jenkins-artifacts-browse,
        # stripping `/artifacts` from the path.
        handle_path /artifacts/* {
          reverse_proxy unix//run/rclone-jenkins-artifacts-browse.sock
        }

        # Proxy all other requests to jenkins as-is, but delegate auth to
        # oauth2-proxy.
        # Also see https://oauth2-proxy.github.io/oauth2-proxy/configuration/integration#configuring-for-use-with-the-caddy-v2-forward_auth-directive

        handle /oauth2/* {
          reverse_proxy localhost:4180 {
            # oauth2-proxy requires the X-Real-IP and X-Forwarded-{Proto,Host,Uri} headers.
            # The reverse_proxy directive automatically sets X-Forwarded-{For,Proto,Host} headers.
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-Uri {uri}
          }
        }

        handle {
          forward_auth localhost:4180 {
            uri /oauth2/auth

            # oauth2-proxy requires the X-Real-IP and X-Forwarded-{Proto,Host,Uri} headers.
            # The forward_auth directive automatically sets the X-Forwarded-{For,Proto,Host,Method,Uri} headers.
            header_up X-Real-IP {remote_host}

            copy_headers {
              X-Auth-Request-User>X-Forwarded-User
              X-Auth-Request-Groups>X-Forwarded-Groups
              X-Auth-Request-Email>X-Forwarded-Mail
              X-Auth-Request-Preferred-Username>X-Forwarded-DisplayName
            }

            # If oauth2-proxy returns a 401 status, redirect the client to the sign-in page.
            @error status 401
            handle_response @error {
              redir * /oauth2/sign_in?rd={scheme}://{host}{uri}
            }
          }
          reverse_proxy localhost:8081
        }
      }
    '';
  };

  services.oauth2-proxy = {
    enable = true;

    # We inject cookie secret, client id and client secret through terraform in cloud-init
    clientID = null;
    clientSecret = null;
    cookie.secret = null;

    provider = "oidc";
    oidcIssuerUrl = "https://auth.vedenemo.dev";
    setXauthrequest = true;
    cookie.secure = false;

    extraConfig = {
      email-domain = "*"; # We require membership in the tiiuae org
      auth-logging = true;
      request-logging = true;
      standard-logging = true;
      reverse-proxy = true; # Needed according to https://oauth2-proxy.github.io/oauth2-proxy/configuration/integration#configuring-for-use-with-the-caddy-v2-forward_auth-directive
      scope = "openid profile email groups"; # pass github teams as jenkins groups
      provider-display-name = "Vedenemo Auth";
      custom-sign-in-logo = "-";
    };
  };

  # Wait for cloud-init mounting before we start oauth2-proxy.
  systemd.services.oauth2-proxy = {
    after = [ "cloud-init.service" ];
    requires = [ "cloud-init.service" ];
    serviceConfig.EnvironmentFile = "/var/lib/oauth2-proxy.env";
  };

  # Wait for cloud-init mounting before we start caddy.
  systemd.services.caddy = {
    after = [ "cloud-init.service" ];
    requires = [ "cloud-init.service" ];
    serviceConfig.EnvironmentFile = "/var/lib/caddy/caddy.env";
  };

  # Configure Nix to use the bucket (through rclone-http) as a substitutor.
  # The public key is passed in externally.
  nix.settings.substituters = [ "http://localhost:8080" ];

  # Expose the HTTP[S] port. We still need HTTP for the HTTP-01 challenge.
  # While TLS-ALPN-01 could be used, disabling HTTP-01 seems only possible from
  # the JSON config, which won't work alongside Caddyfile.
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "24.11";
}
