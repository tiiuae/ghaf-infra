# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  config,
  lib,
  ...
}:
{
  imports = [
    ./disk-config.nix
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    baseline-reset
    hetzner-cloud
    zramSwap
    common
    openssh
    remote-builder
    team-devenv
  ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      cachix-auth-token.owner = "root";
    };
  };

  networking.hostName = "hetzarm-dbg-1";
  virtualisation.hetzner.withEfiSupport = true;

  builder = {
    enable = true;
    sshPublicKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM2rhqSdifRmTwyrc3rvXWyDMznrIAAkVwhEsufLYiTp"
    ];

    # Current host sizing: 16 vCPU, 30 GiB RAM, ~235 GiB writable root (including Nix).
    tuning = {
      enable = true;
      cpus = 16;
      ramGiB = 30;
      diskGiB = 235;
    };

    cachixPush = {
      enable = true;
      cacheName = "ghaf-dbg";
      authTokenFile = config.sops.secrets.cachix-auth-token.path;
    };
  };

  services.baseline-reset = {
    enable = true;
    rootDevice = "/dev/disk/by-partlabel/disk-os-baseline";
  };

  nix.caches = [
    "nixos-org"
    "ghaf-dev"
    "ghaf-dbg"
  ];
  nix.settings.trusted-users = [ "@wheel" ];
  system.stateVersion = lib.mkForce "25.11";
}
