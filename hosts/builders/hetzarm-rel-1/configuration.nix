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
  ]);

  system.stateVersion = "26.05";

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      loki_password.owner = "alloy";
      cachix-auth-token.owner = "root";
    };
  };

  networking.hostName = "hetzarm-rel-1";

  # Current host sizing: 16 vCPU, 30 GiB RAM, ~300 GiB root disk.
  builder.tuning = {
    enable = true;
    cpus = 16;
    ramGiB = 30;
    diskGiB = 300;
  };

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
