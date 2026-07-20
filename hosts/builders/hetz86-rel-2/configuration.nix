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
    ../builders-common.nix
    ../cross-compilation.nix
    ../cachix-push.nix
    ../release-common.nix
    ../../zramswap.nix
    ../../hetzner-robot.nix
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
      cachix-auth-token.owner = "root";
    };
  };

  networking.hostName = "hetz86-rel-2";
  boot.kernelModules = [ "kvm-amd" ];

  # Current host sizing: 96 vCPU, 251 GiB RAM, ~1760 GiB root (/nix) disk.
  builder.tuning = {
    enable = true;
    cpus = 96;
    ramGiB = 251;
    diskGiB = 1760;
  };

  cachix-push = {
    cacheName = "ghaf-release";
  };

  services.monitoring = {
    metrics = {
      enable = true;
      ssh = true;
    };
    logs.enable = true;
  };

  users.users.hetz86-rel-2-builder = {
    isNormalUser = true;
  };
  nix.settings.trusted-users = [
    "hetz86-rel-2-builder"
  ];
}
