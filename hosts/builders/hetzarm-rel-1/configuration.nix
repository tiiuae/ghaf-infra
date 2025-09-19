# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  self,
  inputs,
  ...
}:
{
  imports =
    [
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
    ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      loki_password.owner = "promtail";
      cachix-auth-token.owner = "root";
    };
  };

  nixpkgs.hostPlatform = "aarch64-linux";
  networking.hostName = "hetzarm-rel-1";

  cachix-push = {
    cacheName = "ghaf-release";
  };

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };

  # Nixos-anywhere kexec switch fails on hetzner cloud arm VMs without this
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Ensure only the nixos.org and ghaf-release cachix cache are trusted
  nix.settings.trusted-public-keys = lib.mkForce [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "ghaf-release.cachix.org-1:wvnAftt8aSJ5KukTQb+BvvZYqJ5qzWEk/QHMbn2o+Ag="
  ];
  nix.settings.substituters = lib.mkForce [
    "https://cache.nixos.org/"
    "https://ghaf-release.cachix.org"
  ];
  nix.settings.extra-trusted-public-keys = lib.mkForce [ "" ];
  nix.settings.extra-substituters = lib.mkForce [ "" ];
  nix.settings.trusted-substituters = lib.mkForce [ "" ];

  # hetzci-release can use this as remote builder
  users.users.hetzci-release = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIO9k4r3MqFXlatxzDwZash9U8R8dRhlxyHI050hsCFy"
    ];
  };
  nix.settings.trusted-users = [
    "@wheel"
    "hetzci-release"
  ];
}
