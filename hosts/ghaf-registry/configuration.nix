# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  inputs,
  ...
}:
{
  imports = [
    ./disk-config.nix
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    hetzner-cloud
    common
    zot-registry
    openssh
    team-devenv
  ]);

  sops.defaultSopsFile = ./secrets.yaml;
  system.stateVersion = lib.mkForce "26.05";
  networking.hostName = "ghaf-registry";
  virtualisation.hetzner.withEfiSupport = true;

  services.zot-registry = {
    clientId = "zot-registry";
    domain = "registry.vedenemo.dev";
    metrics.enable = true;
  };

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };
}
