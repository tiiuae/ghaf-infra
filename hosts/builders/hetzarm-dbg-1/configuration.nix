# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  self,
  inputs,
  lib,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ../builders-common.nix
    ../../hetzner-cloud.nix
    ../../zramswap.nix
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    team-devenv
    user-remote-build
  ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
  };

  nixpkgs.hostPlatform = "aarch64-linux";
  networking.hostName = "hetzarm-dbg-1";

  # Nixos-anywhere kexec switch fails on hetzner cloud arm VMs without this
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Ensure only the nixos.org cache is trusted
  nix.settings.trusted-public-keys = lib.mkForce [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  ];
  nix.settings.substituters = lib.mkForce [
    "https://cache.nixos.org/"
  ];
  nix.settings.extra-trusted-public-keys = lib.mkForce [ "" ];
  nix.settings.extra-substituters = lib.mkForce [ "" ];
  nix.settings.trusted-substituters = lib.mkForce [ "" ];
  nix.settings.trusted-users = [ "@wheel" ];

  system.stateVersion = lib.mkForce "25.11";
}
