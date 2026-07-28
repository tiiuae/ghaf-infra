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
    inputs.disko.nixosModules.disko
    ./disk-config.nix
    self.nixosModules.hetzner-cloud
    ./fleet.nix
  ]
  ++ (with self.nixosModules; [
    common
    openssh
    nginx
    team-devenv
    user-vadikas
  ]);

  networking.hostName = "ghaf-fleetdm";
  system.stateVersion = lib.mkForce "25.05";
  sops.defaultSopsFile = ./secrets.yaml;
}
