# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ../common.nix
    ../remote-builders.nix
    ../signing.nix
  ];

  system.stateVersion = lib.mkForce "25.05";
  networking.hostName = "hetzci-vm";
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      cachix-auth-token.owner = "jenkins";
      jenkins_archive_access_key.owner = "jenkins";
      jenkins_archive_secret_key.owner = "jenkins";
      jenkins_github_commit_status_token.owner = "jenkins";
      jenkins_github_webhook_secret.owner = "jenkins";
      oci_registry_password.owner = "jenkins";
    };
  };

  services.ghaf-jenkins = {
    envType = "vm";
    url = "http://localhost:8080";
    integrations = {
      github = {
        enable = true;
        tokenFile = config.sops.secrets.jenkins_github_commit_status_token.path;
        webhookSecretFile = config.sops.secrets.jenkins_github_webhook_secret.path;
      };
      cachix = {
        enable = true;
        tokenFile = config.sops.secrets.cachix-auth-token.path;
      };
    };
    archive = {
      enable = true;
      s3Credentials = {
        accessKeyFile = config.sops.secrets.jenkins_archive_access_key.path;
        secretKeyFile = config.sops.secrets.jenkins_archive_secret_key.path;
      };
    };
    registry.passwordFile = config.sops.secrets.oci_registry_password.path;
    nodes.testagentHosts = [ ];
    pipelines = [
      "ghaf-hw-test-manual"
      "ghaf-hw-test"
      "ghaf-main"
      "ghaf-manual"
      "ghaf-nightly-perftest"
      "ghaf-nightly-poweroff"
      "ghaf-nightly"
      "ghaf-pre-merge-manual"
      "ghaf-pre-merge"
      "ghaf-release-candidate"
      "ghaf-release-publish"
    ];
    extraCasc = {
      jenkins.authorizationStrategy = "unsecured";
    };
  };

  # VM specific configuration:
  virtualisation.vmVariant = {
    virtualisation.sharedDirectories.shr = {
      source = "$HOME/.config/vmshared/hetzci-vm";
      target = "/shared";
    };
  };

  # Stub Caddy config for vm
  services.caddy = {
    enable = true;
    enableReload = false;
    configFile = pkgs.writeText "Caddyfile" ''
      {
        admin off
        debug
        auto_https off
      }

      http://localhost, http://127.0.0.1 {

        # Route /artifacts requests to caddy file_server
        handle_path /artifacts* {
          root * /var/lib/jenkins/artifacts
          file_server {
            browse
          }
        }

        handle {
          reverse_proxy localhost:8081
        }
      }
    '';
  };
}
