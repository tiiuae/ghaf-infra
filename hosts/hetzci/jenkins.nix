# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  self,
  machines,
  inputs,
  ...
}:
let
  cfg = config.hetzci.jenkins;

  # copies only pipelines declared in cfg.pipelines
  filteredPipelines = pkgs.runCommand "pipelines" { } ''
    mkdir -p $out
    ${pkgs.lib.concatMapStringsSep "\n" (name: ''
      cp ${./pipelines}/${name}.groovy "$out/"
    '') cfg.pipelines}
  '';

  # Jenkins shared libraries expect a Git repository. Turn the repository-local
  # pipeline-library sources into a tiny synthetic repo and expose it as
  # /etc/jenkins/pipeline-library for the file:// retriever configured in CasC.
  pipelineSharedLibrary = pkgs.runCommand "pipeline-library" { nativeBuildInputs = [ pkgs.git ]; } ''
    mkdir -p "$out"
    cp -r ${./pipeline-library}/. "$out/"
    chmod -R u+w "$out"
    cd "$out"
    # Create a single deterministic commit so the Nix output is reproducible
    # while still looking like a normal Git repository to Jenkins.
    git init --initial-branch=main
    git add .
    GIT_AUTHOR_DATE="@''${SOURCE_DATE_EPOCH} +0000" \
    GIT_COMMITTER_DATE="@''${SOURCE_DATE_EPOCH} +0000" \
    git -c user.email=nix@example.invalid -c user.name=Nix \
      commit -m "Provision Jenkins shared library"
  '';

  cascConfig = pkgs.writeText "config.yaml" (
    # YAML is a superset of JSON, ie. json is valid yaml
    builtins.toJSON {
      unclassified.location.url = "${cfg.url}";
      jenkins.nodes = # all permutations of device and host lists
        lib.mapCartesianProduct
          (
            { host, device }:
            {
              permanent = {
                name = "${host}-${device}";
                labelString = device;
                launcher = "inbound";
                mode = "EXCLUSIVE";
                remoteFS = "/var/lib/jenkins/agents/${device}";
                retentionStrategy = "always";
              };
            }
          )
          {
            host = cfg.nodes.testagentHosts;
            device = cfg.nodes.devices;
          };
    }
  );
in
{
  options.hetzci.jenkins = {
    envType = lib.mkOption {
      type = lib.types.enum [
        "dbg"
        "dev"
        "prod"
        "release"
        "vm"
      ];
      description = "The type of environment this is";
    };
    url = lib.mkOption {
      type = lib.types.str;
      description = "Public URL of the jenkins instance";
    };
    extraCasc = lib.mkOption {
      type = lib.types.attrs;
      description = "Extra configuration to be added into the jenkins casc";
      default = { };
    };
    pipelines = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Jenkins pipelines to load from the pipelines directory";
      default = [ ];
    };
    nodes = {
      devices = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Devices to create agent nodes for";
        default = [
          "darter-pro"
          "dell-7330"
          "lenovo-x1"
          "orin-agx"
          "orin-agx-64"
          "orin-nx"
          "x1-sec-boot"
        ];
      };
      testagentHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Variations of device nodes to create";
        default = [
          "dev"
          "prod"
          "release"
        ];
      };
    };
    pluginsFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to the plugins.json";
      default = ./plugins.json;
    };
    withCachix = lib.mkOption {
      type = lib.types.bool;
      description = "Add cachix pinning capability";
      default = true;
    };
    withGithubStatus = lib.mkOption {
      type = lib.types.bool;
      description = "Configure a token to set Ghaf GitHub commit satuses";
      default = true;
    };
    withGithubWebhook = lib.mkOption {
      type = lib.types.bool;
      description = "Expected Ghaf GitHub webhook secret";
      default = true;
    };
    withArchiveArtifacts = lib.mkOption {
      type = lib.types.bool;
      description = "Add capability to archive artifacts to permanent storage";
      default = false;
    };
    withRegistryPublish = lib.mkOption {
      type = lib.types.bool;
      description = "Add capability to publish build artifacts to the OCI registry";
      default = false;
    };
  };
  config = {
    sops = {
      secrets = lib.mkMerge [
        (lib.mkIf cfg.withCachix {
          cachix-auth-token.owner = "jenkins";
        })
        (lib.mkIf cfg.withGithubStatus {
          jenkins_github_commit_status_token.owner = "jenkins";
        })
        (lib.mkIf cfg.withGithubWebhook {
          jenkins_github_webhook_secret.owner = "jenkins";
        })
        (lib.mkIf cfg.withArchiveArtifacts {
          jenkins_archive_access_key.owner = "jenkins";
          jenkins_archive_secret_key.owner = "jenkins";
        })
        (lib.mkIf cfg.withRegistryPublish {
          oci_registry_password.owner = "jenkins";
        })
      ];
    };

    services.jenkins = {
      enable = true;
      listenAddress = "localhost";
      port = 8081;
      withCLI = true;
      packages =
        (with pkgs; [
          bashInteractive # 'sh' step in jenkins pipeline requires this
          coreutils
          colorized-logs
          csvkit
          curl
          git
          gnutar
          hostname
          jq
          nix
          openssh
          wget
          zstd
        ])
        ++ [
          inputs.sbomnix.packages.${pkgs.stdenv.hostPlatform.system}.sbomnix # provenance
        ]
        ++ lib.optionals cfg.withCachix [
          pkgs.cachix
          pkgs.nixos-rebuild
        ]
        ++ lib.optionals cfg.withArchiveArtifacts [
          pkgs.tree
          self.packages.${pkgs.stdenv.hostPlatform.system}.archive-ghaf-release
        ]
        ++ lib.optionals cfg.withRegistryPublish [
          pkgs.oras
          self.packages.${pkgs.stdenv.hostPlatform.system}.oci-publish
        ];

      environment = {
        CI_ENV = cfg.envType;
      };

      extraJavaOptions = [
        # Useful when the 'sh' step fails:
        "-Dorg.jenkinsci.plugins.durabletask.BourneShellScript.LAUNCH_DIAGNOSTICS=true"
        # If we want to allow robot framework reports, we need to adjust Jenkins CSP:
        # https://plugins.jenkins.io/robot/#plugin-content-log-file-not-showing-properly
        "-Dhudson.model.DirectoryBrowserSupport.CSP=\"sandbox allow-scripts; default-src 'none'; img-src 'self' data: ; style-src 'self' 'unsafe-inline' data: ; script-src 'self' 'unsafe-inline' 'unsafe-eval';\""
        # Point to configuration-as-code config
        "-Dcasc.jenkins.config=/etc/jenkins/casc"
        # Disable the initial setup wizard, and the creation of initialAdminPassword.
        "-Djenkins.install.runSetupWizard=false"
        # Shared library retrieval uses file:///etc/jenkins/pipeline-library.
        "-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true"
        # Allow setting the following possibly undefined parameters
        "-Dhudson.model.ParametersAction.safeParameters=DESC,RELOAD_ONLY,GHAF_FLAKE_REF"
        # Ensure workspace root dir is what we expect
        ''-Djenkins.model.Jenkins.workspacesDir=$JENKINS_HOME/workspace/\$ITEM_FULL_NAME''
      ];
      plugins =
        let
          manifest = builtins.fromJSON (builtins.readFile cfg.pluginsFile);

          mkJenkinsPlugin =
            {
              name,
              version,
              url,
              sha256,
            }:
            lib.nameValuePair name (
              pkgs.stdenv.mkDerivation {
                inherit name version;
                src = pkgs.fetchurl {
                  inherit url sha256;
                };
                phases = "installPhase";
                installPhase = "cp \$src \$out";
              }
            );
        in
        builtins.listToAttrs (map mkJenkinsPlugin manifest);
    };

    # Caddy needs to be able to access files under /var/lib/jenkins/artifacts.
    # Use traverse-only access on JENKINS_HOME and scope group access to caddy.service.
    users.users.jenkins.homeMode = "710";
    systemd.services.caddy.serviceConfig.SupplementaryGroups = [ "jenkins" ];

    environment.etc = lib.mkMerge [
      {
        "jenkins/nix-fast-build.sh".source = "${self.outPath}/scripts/nix-fast-build.sh";
        "jenkins/pipelines".source = filteredPipelines;
        "jenkins/pipeline-library".source = pipelineSharedLibrary;
        "jenkins/casc/common.yaml".source = ./casc/common.yaml;
        "jenkins/casc/config.yaml".source = cascConfig;
        "jenkins/casc/extraConfig.yaml".source = pkgs.writeText "extraConfig.yaml" (
          builtins.toJSON cfg.extraCasc
        );
      }
      (lib.mkIf cfg.withCachix {
        "jenkins/casc/cachix.yaml".source = ./casc/cachix.yaml;
      })
      (lib.mkIf cfg.withGithubStatus {
        "jenkins/casc/githubToken.yaml".source = ./casc/githubToken.yaml;
      })
      (lib.mkIf cfg.withGithubWebhook {
        "jenkins/casc/githubWebhook.yaml".source = ./casc/githubWebhook.yaml;
      })
      (lib.mkIf cfg.withArchiveArtifacts {
        "jenkins/casc/archiveArtifacts.yaml".source = ./casc/archiveArtifacts.yaml;
      })
      (lib.mkIf cfg.withRegistryPublish {
        "jenkins/casc/registryPublish.yaml".source = ./casc/registryPublish.yaml;
      })
    ];

    systemd.services.jenkins = {
      # Ensure plugins dir exists before the module-generated preStart script
      # runs `rm -r /var/lib/jenkins/plugins`, to avoid first-boot noise.
      preStart = lib.mkBefore ''
        mkdir -p /var/lib/jenkins/plugins
      '';
      serviceConfig = {
        Restart = "on-failure";
      };
    };

    # Remove all config files from jenkins home before loading the casc.
    # This ensures there's no lingering config from the past,
    # and only what is in the casc is regenerated
    systemd.services.jenkins-config-cleanup = {
      before = [ "jenkins.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "jenkins";
        WorkingDirectory = "/var/lib/jenkins";
      };
      script = # sh
        ''
          rm -f *.xml
          rm -rf nodes/*/
          rm -f jobs/*/config.xml
        '';
    };

    systemd.services.jenkins-purge-artifacts = {
      after = [ "jenkins.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "jenkins";
        WorkingDirectory = "/var/lib/jenkins";
      };
      path = with pkgs; [
        coreutils
        nix
      ];
      script = builtins.readFile ./purge-jenkins-artifacts.sh;
    };

    systemd.timers.jenkins-purge-artifacts = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "minutely";
      };
    };

    # users used by testagents to ssh in and collect their secret
    users.users = {
      testagent-dev = {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ machines.testagent-dev.publicKey ];
      };
      testagent-dbg = {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ machines.testagent-dbg.publicKey ];
      };
      testagent2-prod = {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ machines.testagent2-prod.publicKey ];
      };
      testagent-prod = {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ machines.testagent-prod.publicKey ];
      };
      testagent-release = {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ machines.testagent-release.publicKey ];
      };
      uae-testagent-prod = {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ machines.uae-testagent-prod.publicKey ];
      };
      uae-testagent2-prod = {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ machines.uae-testagent2-prod.publicKey ];
      };
    };
  };
}
