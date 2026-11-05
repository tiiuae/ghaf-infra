# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  inputs,
  lib,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ../../azureci/azure-common.nix
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    zot-registry
    openssh
    team-devenv
  ]);

  sops.defaultSopsFile = ./secrets.yaml;

  # this server has been initialized with 26.05 with nixos-anywhere
  system.stateVersion = lib.mkForce "26.05";

  networking.hostName = "uae-azureci-registry";

  # Use local filesystem storage until the AWS S3 me-central-1 outage is resolved.
  services.zot-registry = {
    clientId = "uae-zot-registry";
    domain = "registry.uaenorth.cloudapp.azure.com";
    metrics.enable = true;
    # SFO images contain proprietary bundles; never inherit the public fallback.
    extraConfig.http.accessControl.repositories."sfo/**" = {
      policies = [
        {
          users = [ "sfo-jenkins" ];
          actions = [
            "read"
            "create"
            "update"
            "delete"
          ];
        }
      ];
      defaultPolicy = [ ];
      anonymousPolicy = [ ];
    };
  };

  environment.systemPackages = with pkgs; [
    screen
    tmux
    cryptsetup
    sg3_utils
    dnsutils
    inetutils
    pciutils
    dmidecode
    jq
  ];
}
