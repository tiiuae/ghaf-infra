# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  tuning = import ../../lib/nix-tuning.nix { inherit lib; };

  # Current host sizing: 16 vCPU, 61 GiB RAM, ~3740 GiB /nix disk.
  controllerDisk = tuning.mkDiskThresholds 3740;
in
{
  imports = [
    ./disk-config.nix
    ../common.nix
    ../remote-builders.nix
    ../cloud.nix
    ../signing.nix
  ];

  system.stateVersion = lib.mkForce "24.11";
  networking.hostName = "hetzci-prod";
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      jenkins_github_commit_status_token.owner = "jenkins";
      jenkins_github_webhook_secret.owner = "jenkins";
      jenkins_jira_token.owner = "jenkins";
      oauth2_proxy_client_secret.owner = "oauth2-proxy";
      oauth2_proxy_cookie_secret.owner = "oauth2-proxy";
      oci_registry_password.owner = "jenkins";
    };
  };

  services.ghaf-jenkins = {
    envType = "prod";
    url = "https://ci-prod.vedenemo.dev";
    auth = {
      enable = true;
      clientID = "hetzci-prod";
      clientSecretFile = config.sops.secrets.oauth2_proxy_client_secret.path;
      cookieSecretFile = config.sops.secrets.oauth2_proxy_cookie_secret.path;
      domain = "ci-prod.vedenemo.dev";
    };
    integrations = {
      github = {
        enable = true;
        tokenFile = config.sops.secrets.jenkins_github_commit_status_token.path;
        webhookSecretFile = config.sops.secrets.jenkins_github_webhook_secret.path;
      };
      jira = {
        enable = true;
        tokenFile = config.sops.secrets.jenkins_jira_token.path;
      };
    };
    registry.passwordFile = config.sops.secrets.oci_registry_password.path;
    pipelines = [
      "ghaf-hw-test-manual"
      "ghaf-hw-test"
      "ghaf-main"
      "ghaf-manual"
      "ghaf-nightly-perftest"
      "ghaf-nightly"
      "ghaf-pre-merge-manual"
      "ghaf-pre-merge"
    ];
  };

  hetzci.signing.proxy.enable = true;

  nix.settings.max-jobs = lib.mkForce 0;
  nix.settings.min-free = lib.mkOverride 40 controllerDisk.minFreeBytes;
  nix.settings.max-free = lib.mkOverride 40 controllerDisk.maxFreeBytes;
}
