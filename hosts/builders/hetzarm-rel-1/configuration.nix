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
    hetzner-cloud
    zramSwap
    common
    openssh
    remote-builder
    team-devenv
  ]);

  system.stateVersion = "26.11";

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      loki_password.owner = "alloy";
      cachix-auth-token.owner = "root";
    };
  };

  networking.hostName = "hetzarm-rel-1";
  virtualisation.hetzner.withEfiSupport = true;

  builder = {
    enable = true;
    sshUser = "${config.networking.hostName}-builder";
    sshTrustedCAFile = "/var/lib/baseline-reset/release-builder-ca.pub";

    # Current host sizing: 16 vCPU, 30 GiB RAM, ~235 GiB writable root (including Nix).
    tuning = {
      enable = true;
      cpus = 16;
      ramGiB = 30;
      diskGiB = 235;
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
    rootDevice = "/dev/disk/by-partlabel/disk-os-baseline";
    persistentFiles = [ "release-builder-ca.pub" ];
  };

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };
}
