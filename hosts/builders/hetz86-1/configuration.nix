# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  config,
  ...
}:
{
  imports =
    [
      ./disk-config.nix
      ../developers.nix
      ../builders-common.nix
      ../../hetzner-robot.nix
      inputs.disko.nixosModules.disko
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
      team-devenv
      user-github
      user-remote-build
    ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      cachix-auth-token.owner = "root";
    };
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "hetz86-1";

  boot.kernelModules = [ "kvm-amd" ];

  services.monitoring = {
    metrics = {
      enable = true;
      ssh = true;
    };
    logs.enable = true;
  };

  services.cachix-watch-store = {
    enable = true;
    verbose = true;
    cacheName = "ghaf-dev";
    cachixTokenFile = config.sops.secrets.cachix-auth-token.path;
  };
}
