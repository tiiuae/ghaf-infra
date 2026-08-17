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
    self.nixosModules.hetzner-cloud
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    openssh
    nebula
    team-devenv
  ]);

  sops.defaultSopsFile = ./secrets.yaml;

  system.stateVersion = lib.mkForce "25.05";
  networking.hostName = "ghaf-lighthouse";

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };

  nebula = {
    enable = true;
    isLighthouse = true;
  };
}
