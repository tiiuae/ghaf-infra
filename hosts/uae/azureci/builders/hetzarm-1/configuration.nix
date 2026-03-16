# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  inputs,
  modulesPath,
  lib,
  ...
}:
let
  tuning = import ../../../../lib/nix-tuning.nix { inherit lib; };

  # Current host sizing: 16 vCPU, 32 GiB RAM, ~1024 GiB /nix disk.
  disk = tuning.mkDiskThresholds 1024;
  jobs = tuning.mkMaxJobs {
    cpus = 16;
    ramGiB = 32;
  };
in
{
  imports = [
    ./disk-config.nix
    ../../../../hetzner-robot.nix
    ../../../../builders/builders-common.nix
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    team-devenv
    user-github
    user-uae-remote-build
  ]);

  # this server has been initialized with 25.05 with nixos-anywhere
  system.stateVersion = lib.mkForce "25.05";
  nixpkgs.hostPlatform = "aarch64-linux";

  networking.hostName = "uae-azureci-hetzarm-1";

  sops.defaultSopsFile = ./secrets.yaml;

  nix.settings.max-jobs = lib.mkForce jobs;
  nix.settings.cores = lib.mkForce 2;
  nix.settings.min-free = lib.mkForce disk.minFreeBytes;
  nix.settings.max-free = lib.mkForce disk.maxFreeBytes;

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
