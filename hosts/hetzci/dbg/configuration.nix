# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  machines,
  ...
}:
let
  tuning = import ../../lib/nix-tuning.nix { inherit lib; };
  trustedBuilderHost = host: "${host}?trusted=true";

  # Current host sizing: 16 vCPU, 30 GiB RAM, ~300 GiB root disk.
  controllerDisk = tuning.mkDiskThresholds 300;
  builderMaxJobs = tuning.mkMaxJobs {
    cpus = 16;
    ramGiB = 30;
  };
in
{
  imports = [
    ./disk-config.nix
    ../common.nix
    ../jenkins.nix
    ../cloud.nix
    ../auth.nix
    ../signing.nix
  ];

  system.stateVersion = lib.mkForce "25.11";
  networking.hostName = "hetzci-dbg";
  ghaf.nix-cache.caches = [
    "nixos-org"
    "ghaf-dbg"
  ];

  hetzci = {
    jenkins = {
      envType = "dbg";
      url = "https://ci-dbg.vedenemo.dev";
      nodes.testagentHosts = [
        "dev"
        "prod"
        "release"
        "dbg"
      ];
      pipelines = [
        "ghaf-hw-test-manual"
        "ghaf-hw-test"
        "ghaf-manual"
        "ghaf-release-candidate"
      ];
      withRegistryPublish = true;
      withCachix = false;
      withGithubStatus = false;
      withGithubWebhook = false;
    };
    auth = {
      clientID = "hetzci-dbg";
      domain = "ci-dbg.vedenemo.dev";
    };
    signing.proxy.enable = true;
  };

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      vedenemo_builder_ssh_key.owner = "root";
    };
  };

  services.monitoring = {
    metrics.enable = lib.mkForce false;
    logs.enable = lib.mkForce false;
  };

  # Configure /var/lib/caddy in /etc/fstab for persistent caddy state.
  fileSystems."/var/lib/caddy" = {
    device = "/dev/disk/by-id/scsi-0HC_Volume_104714167";
    fsType = "ext4";
    options = [
      "x-systemd.makefs"
      "x-systemd.growfs"
    ];
  };

  nix = {
    distributedBuilds = true;
    settings = {
      # Keep Jenkins/controller workloads off local builds.
      max-jobs = lib.mkForce 0;
      min-free = lib.mkOverride 40 controllerDisk.minFreeBytes;
      max-free = lib.mkOverride 40 controllerDisk.maxFreeBytes;
    };
    buildMachines =
      let
        commonOptions = {
          speedFactor = 10;
          supportedFeatures = [
            "kvm"
            "nixos-test"
            "benchmark"
            "big-parallel"
          ];
        };
      in
      [
        (
          {
            hostName = trustedBuilderHost machines.hetzarm-dbg-1.ip;
            system = "aarch64-linux";
            maxJobs = builderMaxJobs;
          }
          // commonOptions
        )
        (
          {
            hostName = trustedBuilderHost machines.hetz86-dbg-1.ip;
            system = "x86_64-linux";
            maxJobs = builderMaxJobs;
          }
          // commonOptions
        )
      ];
  };

  programs.ssh = {
    knownHosts = {
      "${machines.hetz86-dbg-1.ip}".publicKey = machines.hetz86-dbg-1.publicKey;
      "${machines.hetzarm-dbg-1.ip}".publicKey = machines.hetzarm-dbg-1.publicKey;
    };

    # Custom options to /etc/ssh/ssh_config
    extraConfig = lib.mkAfter ''
      Host ${machines.hetz86-dbg-1.ip}
      Hostname ${machines.hetz86-dbg-1.ip}
      User remote-build
      IdentityFile ${config.sops.secrets.vedenemo_builder_ssh_key.path}

      Host ${machines.hetzarm-dbg-1.ip}
      Hostname ${machines.hetzarm-dbg-1.ip}
      User remote-build
      IdentityFile ${config.sops.secrets.vedenemo_builder_ssh_key.path}
    '';
  };
}
