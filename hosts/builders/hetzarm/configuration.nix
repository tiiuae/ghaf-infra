# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  ...
}:
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
}
