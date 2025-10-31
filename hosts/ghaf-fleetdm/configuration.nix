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
  imports =
    [
      ./disk-config.nix
      ../hetzner-cloud.nix
      inputs.sops-nix.nixosModules.sops
      inputs.disko.nixosModules.disko
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
      team-devenv
      user-vadikas
    ]);

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "ghaf-fleetdm";
  system.stateVersion = lib.mkForce "25.05";
  sops.defaultSopsFile = ./secrets.yaml;

  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    fleet
    fleetctl
  ];
}
