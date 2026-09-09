# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ../builders-common.nix
    ../cachix-push.nix
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    hetzner-cloud
    zramSwap
    common
    openssh
    team-devenv
    user-remote-build
  ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      cachix-auth-token.owner = "root";
    };
  };

  networking.hostName = "hetzarm-dbg-1";
  virtualisation.hetzner.withEfiSupport = true;

  # Current host sizing: 16 vCPU, 30 GiB RAM, ~300 GiB root disk.
  builder.tuning = {
    enable = true;
    cpus = 16;
    ramGiB = 30;
    diskGiB = 300;
  };

  cachix-push = {
    cacheName = "ghaf-dbg";
  };

  nix.caches = [
    "nixos-org"
    "ghaf-dbg"
  ];
  nix.settings.trusted-users = [ "@wheel" ];
  system.stateVersion = lib.mkForce "25.11";
}
