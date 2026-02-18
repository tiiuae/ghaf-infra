# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  self,
  inputs,
  lib,
  ...
}:
let
  tuning = import ../../lib/nix-tuning.nix { inherit lib; };

  # Current host sizing: 16 vCPU, 30 GiB RAM, ~300 GiB root disk.
  disk = tuning.mkDiskThresholds 300;
  jobs = tuning.mkMaxJobs {
    cpus = 16;
    ramGiB = 30;
  };
in
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
  nix.settings.max-jobs = lib.mkForce jobs;
  nix.settings.cores = lib.mkForce 2;
  nix.settings.min-free = lib.mkForce disk.minFreeBytes;
  nix.settings.max-free = lib.mkForce disk.maxFreeBytes;

  system.stateVersion = lib.mkForce "25.11";
}
