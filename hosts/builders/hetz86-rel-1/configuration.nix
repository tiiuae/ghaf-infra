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
      loki_password.owner = "alloy";
      cachix-auth-token.owner = "root";
    };
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "hetz86-rel-1";
  boot.kernelModules = [ "kvm-amd" ];

  cachix-push = {
    cacheName = "ghaf-release";
  };

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };
}
