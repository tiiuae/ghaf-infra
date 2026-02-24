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

  # Current host sizing: 80 vCPU, 250 GiB RAM, ~3520 GiB /nix disk.
  disk = tuning.mkDiskThresholds 3520;
  jobs = tuning.mkMaxJobs {
    cpus = 80;
    ramGiB = 250;
  };
in
{
  imports = [
    ./disk-config.nix
    ../developers.nix
    ../builders-common.nix
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

  nixpkgs.hostPlatform = "aarch64-linux";
  networking.hostName = "hetzarm";

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

  # hetz86-builder can use this as remote builder
  users.users.hetz86-builder = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFZVnXp7IosGUWb0xj5NSJKAUcTIO9VIfbRD6K28eLxc"
    ];
  };

  nix.settings.trusted-users = [
    "@wheel"
    "hetz86-builder"
  ];
  nix.settings.max-jobs = lib.mkForce jobs;
  nix.settings.cores = lib.mkForce 2;
  nix.settings.min-free = lib.mkForce disk.minFreeBytes;
  nix.settings.max-free = lib.mkForce disk.maxFreeBytes;
}
