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
    ../cross-compilation.nix
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

  networking.hostName = "hetz86-dbg-1";
  boot.kernelModules = [ "kvm-amd" ];

  # Current host sizing: 16 vCPU, 30 GiB RAM, ~337 GiB root disk.
  builder.tuning = {
    enable = true;
    cpus = 16;
    ramGiB = 30;
    diskGiB = 337;
  };

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
