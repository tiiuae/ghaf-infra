# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  self,
  inputs,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ../builders-common.nix
    ../cachix-push.nix
    ../release-common.nix
    ../../hetzner-cloud.nix
    ../../zramswap.nix
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    team-devenv
    user-ctsopokis
  ]);

  system.stateVersion = "25.05";

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      loki_password.owner = "alloy";
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

  users.users.hetzarm-rel-1-builder = {
    isNormalUser = true;
  };
  nix.settings.trusted-users = [
    "hetzarm-rel-1-builder"
  ];

  # Nixos-anywhere kexec switch fails on hetzner cloud arm VMs without this
  boot.kernelPackages = pkgs.linuxPackages_latest;
}
