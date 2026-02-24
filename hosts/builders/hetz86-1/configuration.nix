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

  # Current host sizing: 96 vCPU, 251 GiB RAM, ~1760 GiB /nix disk.
  disk = tuning.mkDiskThresholds 1760;
  jobs = tuning.mkMaxJobs {
    cpus = 96;
    ramGiB = 251;
  };
in
{
  imports = [
    ./disk-config.nix
    ../developers.nix
    ../builders-common.nix
    ../cross-compilation.nix
    ../cachix-push.nix
    ../../hetzner-robot.nix
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    team-devenv
    user-github
    user-remote-build
  ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      cachix-auth-token.owner = "root";
    };
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "hetz86-1";
  boot.kernelModules = [ "kvm-amd" ];

  cachix-push = {
    cacheName = "ghaf-dev";
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
}
