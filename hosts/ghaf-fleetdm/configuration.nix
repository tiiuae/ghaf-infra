# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  ...
}:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
    ./disk-config.nix
    ../hetzner-cloud.nix
    ./fleet.nix
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    service-nginx
    team-devenv
    user-vadikas
  ]);

  networking.hostName = "ghaf-fleetdm";
  system.stateVersion = lib.mkForce "25.05";
  sops.defaultSopsFile = ./secrets.yaml;
}
