# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  ...
}:
let
  tuning = import ../../lib/nix-tuning.nix { inherit lib; };

  # Current host sizing: 96 vCPU, 251 GiB RAM, ~1760 GiB root (/nix) disk.
  disk = tuning.mkDiskThresholds 1760;
  jobs = tuning.mkMaxJobs {
    cpus = 96;
    ramGiB = 251;
  };
in
{
  imports = [
    ./disk-config.nix
    ../builders-common.nix
    ../cross-compilation.nix
    ../cachix-push.nix
    ../release-common.nix
    ../../zramswap.nix
    ../../hetzner-robot.nix
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    team-devenv
    user-ctsopokis
  ]);

  system.stateVersion = "25.11";

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      cachix-auth-token.owner = "root";
    };
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "hetz86-rel-2";
  boot.kernelModules = [ "kvm-amd" ];

  cachix-push = {
    cacheName = "ghaf-release";
  };

  services.monitoring = {
    metrics = {
      enable = true;
      ssh = true;
    };
    logs.enable = true;
  };

  nix.settings.max-jobs = lib.mkForce jobs;
  nix.settings.cores = lib.mkForce 2;
  nix.settings.min-free = lib.mkForce disk.minFreeBytes;
  nix.settings.max-free = lib.mkForce disk.maxFreeBytes;

  users.users.hetz86-rel-2-builder = {
    isNormalUser = true;
  };
  nix.settings.trusted-users = [
    "hetz86-rel-2-builder"
  ];
}
