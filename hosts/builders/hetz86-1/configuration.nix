# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  config,
  ...
}:
{
  imports = [
    ./disk-config.nix
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    hetzner-robot
    common
    openssh
    remote-builder
    team-devenv
    team-developers
    user-github
  ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      cachix-auth-token.owner = "root";
    };
  };

  system.stateVersion = "23.11";
  networking.hostName = "hetz86-1";
  boot.kernelModules = [ "kvm-amd" ];

  builder = {
    enable = true;
    sshPublicKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM2rhqSdifRmTwyrc3rvXWyDMznrIAAkVwhEsufLYiTp"
    ];
    crossCompilation.enable = true;

    # Current host sizing: 96 vCPU, 251 GiB RAM, ~1760 GiB /nix disk.
    tuning = {
      enable = true;
      cpus = 96;
      ramGiB = 251;
      diskGiB = 1760;
    };

    cachixPush = {
      enable = true;
      cacheName = "ghaf-dev";
      authTokenFile = config.sops.secrets.cachix-auth-token.path;
    };
  };

  services.monitoring = {
    metrics = {
      enable = true;
      ssh = true;
    };
    logs.enable = true;
  };
}
