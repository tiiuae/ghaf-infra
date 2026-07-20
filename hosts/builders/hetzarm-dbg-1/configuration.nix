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
    ../cachix-push.nix
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
    secrets = {
      cachix-auth-token.owner = "root";
    };
  };

  networking.hostName = "hetzarm-dbg-1";

  # Current host sizing: 16 vCPU, 30 GiB RAM, ~300 GiB root disk.
  builder.tuning = {
    enable = true;
    cpus = 16;
    ramGiB = 30;
    diskGiB = 300;
  };

  # Nixos-anywhere kexec switch fails on hetzner cloud arm VMs without this
  boot.kernelPackages = pkgs.linuxPackages_latest;

  cachix-push = {
    cacheName = "ghaf-dbg";
  };

  ghaf.nix-cache.caches = [
    "nixos-org"
    "ghaf-dbg"
  ];
  nix.settings.trusted-users = [ "@wheel" ];
  system.stateVersion = lib.mkForce "25.11";
}
