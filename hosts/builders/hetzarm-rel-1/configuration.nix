# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  self,
  inputs,
  config,
  ...
}:
{
  imports =
    [
      ./disk-config.nix
      ../builders-common.nix
      ../../hetzner-cloud.nix
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
      cachix-auth-token.owner = "root";
      loki_password.owner = "promtail";
    };
  };

  nixpkgs.hostPlatform = "aarch64-linux";
  networking.hostName = "hetzarm-rel-1";

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };

  # Enable zramSwap: https://search.nixos.org/options?show=zramSwap.enable
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 150;
  };
  # https://wiki.archlinux.org/title/Zram#Optimizing_swap_on_zram:
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
    "vm.page-cluster" = 0;
  };

  # Nixos-anywhere kexec switch fails on hetzner cloud arm VMs without this
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Disable cachix push for now, until we setup an own
  # cache for release builds
  services.cachix-watch-store = {
    enable = false;
    verbose = true;
    cacheName = "ghaf-dev";
    cachixTokenFile = config.sops.secrets.cachix-auth-token.path;
  };

  # Ensure only the nixos.org cache is trusted
  nix.settings.trusted-public-keys = lib.mkForce [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  ];
  nix.settings.substituters = lib.mkForce [ "https://cache.nixos.org/" ];
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
