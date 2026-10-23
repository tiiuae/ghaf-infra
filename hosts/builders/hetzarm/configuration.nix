# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  config,
  ...
}:
{
  imports = [
    ./disk-config.nix
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    hetzner-robot
    common
    openssh
    remote-builder
    team-devenv
    team-developers
    user-github
  ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      cachix-auth-token.owner = "root";
    };
  };

  system.stateVersion = "23.11";
  networking.hostName = "hetzarm";

  builder = {
    enable = true;
    sshPublicKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM2rhqSdifRmTwyrc3rvXWyDMznrIAAkVwhEsufLYiTp"
    ];

    # Current host sizing: 80 vCPU, 250 GiB RAM, ~3520 GiB /nix disk.
    tuning = {
      enable = true;
      cpus = 80;
      ramGiB = 250;
      diskGiB = 3520;
    };

    cachixPush = {
      enable = true;
      cacheName = "ghaf-dev";
      authTokenFile = config.sops.secrets.cachix-auth-token.path;
    };
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
}
