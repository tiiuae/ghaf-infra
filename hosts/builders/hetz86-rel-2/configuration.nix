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
    user-ctsopokis
  ]);

  system.stateVersion = "25.05";

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      cachix-auth-token.owner = "root";
    };
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "hetz86-rel-2";
  boot.kernelModules = [ "kvm-amd" ];

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
