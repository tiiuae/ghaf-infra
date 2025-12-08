# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  inputs,
  modulesPath,
  lib,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ../azure-common.nix
    ../remote-builders.nix
    ../../../hetzci/auth.nix
    ../../../hetzci/common.nix
    ../../../hetzci/jenkins.nix
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.disko.nixosModules.disko
  ];

  # this server has been initialized with 25.05 with nixos-anywhere
  # initializing fails with 24.11
  system.stateVersion = lib.mkForce "25.05";
  sops.defaultSopsFile = ./secrets.yaml;

  networking.hostName = "uae-azureci-prod";

  hetzci = {
    jenkins = {
      envType = "prod";
      pluginsFile = ./plugins.json;
      url = "https://ci-prod.uaenorth.cloudapp.azure.com";
      pipelines = [
        "ghaf-hw-test-manual"
        "ghaf-hw-test"
        "ghaf-main"
        "ghaf-manual"
        "ghaf-nightly"
      ];
      withCachix = false;
    };
    auth = {
      clientID = "azureci-prod";
      domain = "ci-prod.uaenorth.cloudapp.azure.com";
    };
  };
}
