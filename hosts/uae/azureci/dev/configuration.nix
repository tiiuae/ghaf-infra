# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  inputs,
  modulesPath,
  lib,
  ...
}:
{
  imports = [
    ../../common.nix
    ./disk-config.nix
    ../azure-common.nix
    ../remote-builders.nix
    ../../../hetzci/common.nix
    ../../../hetzci/signing.nix
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.disko.nixosModules.disko
  ];

  # this server has been initialized with 25.11 with nixos-anywhere
  system.stateVersion = lib.mkForce "25.11";
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      jenkins_github_commit_status_token.owner = "jenkins";
      jenkins_github_webhook_secret.owner = "jenkins";
      oauth2_proxy_client_secret.owner = "oauth2-proxy";
      oauth2_proxy_cookie_secret.owner = "oauth2-proxy";
      oci_registry_password.owner = "jenkins";
    };
  };

  networking.hostName = "uae-azureci-dev";

  services.ghaf-jenkins = {
    envType = "dev";
    url = "https://ci-dev.uaenorth.cloudapp.azure.com";
    registry = {
      url = "registry.uaenorth.cloudapp.azure.com";
      passwordFile = config.sops.secrets.oci_registry_password.path;
    };
    auth = {
      enable = true;
      clientID = "azureci-dev";
      clientSecretFile = config.sops.secrets.oauth2_proxy_client_secret.path;
      cookieSecretFile = config.sops.secrets.oauth2_proxy_cookie_secret.path;
      domain = "ci-dev.uaenorth.cloudapp.azure.com";
    };
    integrations.github = {
      enable = true;
      tokenFile = config.sops.secrets.jenkins_github_commit_status_token.path;
      webhookSecretFile = config.sops.secrets.jenkins_github_webhook_secret.path;
    };
    pipelines = [
      "ghaf-hw-test-manual"
      "ghaf-hw-test"
      "ghaf-manual"
      "g4h-manual"
    ];
  };

  hetzci.signing.proxy.enable = true;

  services.jenkins.environment.ROUTER_PKCS11_REGIONS = "uae,tampere";
}
