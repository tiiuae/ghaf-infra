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
    baseline-reset
    zramSwap
    hetzner-robot
    common
    openssh
    remote-builder
    team-devenv
  ]);

  system.stateVersion = "26.11";

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      cachix-auth-token.owner = "root";
    };
  };

  networking.hostName = "hetz86-rel-2";
  boot.kernelModules = [ "kvm-amd" ];

  builder = {
    enable = true;
    sshUser = "${config.networking.hostName}-builder";
    sshTrustedCAFile = "/var/lib/baseline-reset/release-builder-ca.pub";
    crossCompilation.enable = true;

    # Current host sizing: 96 vCPU, 251 GiB RAM, ~1696 GiB writable Nix partition.
    tuning = {
      enable = true;
      cpus = 96;
      ramGiB = 251;
      diskGiB = 1696;
    };

    cachixPush = {
      enable = true;
      cacheName = "ghaf-release";
      authTokenFile = config.sops.secrets.cachix-auth-token.path;
    };
  };

  nix.caches = [
    "nixos-org"
    "ghaf-release"
  ];

  services.baseline-reset = {
    enable = true;
    rootDevice = "/dev/disk/by-partlabel/disk-nvme0-baseline";
    nixDevice = "/dev/disk/by-partlabel/disk-nvme1-baseline";
    persistentFiles = [ "release-builder-ca.pub" ];
  };

  services.monitoring = {
    metrics = {
      enable = true;
      ssh = true;
    };
    logs.enable = true;
  };
}
