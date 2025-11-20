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
in
{
  options.hetzci.jenkins = {
    casc = lib.mkOption {
      type = lib.types.path;
      description = "Path to the Jenkins CASC";
    };
    pluginsFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to the plugins.json";
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
          inputs.sbomnix.packages.${pkgs.system}.sbomnix # provenance
        ]
        ++ lib.optionals cfg.withCachix [
          pkgs.cachix
          pkgs.nixos-rebuild
        ];

      extraJavaOptions = [
        # Useful when the 'sh' step fails:
        "-Dorg.jenkinsci.plugins.durabletask.BourneShellScript.LAUNCH_DIAGNOSTICS=true"
        # If we want to allow robot framework reports, we need to adjust Jenkins CSP:
        # https://plugins.jenkins.io/robot/#plugin-content-log-file-not-showing-properly
        "-Dhudson.model.DirectoryBrowserSupport.CSP=\"sandbox allow-scripts; default-src 'none'; img-src 'self' data: ; style-src 'self' 'unsafe-inline' data: ; script-src 'self' 'unsafe-inline' 'unsafe-eval';\""
        # Point to configuration-as-code config
        "-Dcasc.jenkins.config=${cfg.casc}"
        # Disable the initial setup wizard, and the creation of initialAdminPassword.
        "-Djenkins.install.runSetupWizard=false"
        # Allow setting the following possibly undefined parameters
        "-Dhudson.model.ParametersAction.safeParameters=DESC,RELOAD_ONLY"
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

    # Jenkins home dir (by default at /var/lib/jenkins) mode needs to be 755
    users.users.jenkins.homeMode = "755";

    environment.etc."jenkins/pipelines".source = cfg.casc + /pipelines;
    environment.etc."jenkins/nix-fast-build.sh".source = "${self.outPath}/scripts/nix-fast-build.sh";

    systemd.services.jenkins = {
      serviceConfig = {
        Restart = "on-failure";
      };
    };

    systemd.services.jenkins-purge-artifacts = {
      after = [ "jenkins.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "jenkins";
        WorkingDirectory = "/var/lib/jenkins";
      };
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
      testagent-uae-dev = {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ machines.testagent-uae-dev.publicKey ];
      };
    };
  };
}
