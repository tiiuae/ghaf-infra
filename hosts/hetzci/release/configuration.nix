# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  machines,
  ...
}:
let
  tuning = import ../../lib/nix-tuning.nix { inherit lib; };

  # Current host sizing: 16 vCPU, 30 GiB RAM, ~337 GiB root disk.
  controllerDisk = tuning.mkDiskThresholds 337;

  # Current release builder sizing:
  # - hetz86-rel-2: 96 vCPU, 251 GiB RAM
  # - hetzarm-rel-1: 16 vCPU, 30 GiB RAM
  x86BuilderMaxJobs = tuning.mkMaxJobs {
    cpus = 96;
    ramGiB = 251;
  };
  armBuilderMaxJobs = tuning.mkMaxJobs {
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
    self.nixosModules.user-ctsopokis
  ];

  system.stateVersion = "25.05";
  networking.hostName = "hetzci-release";

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      ssh_private_key.owner = "root";
    };
  };

  hetzci = {
    jenkins = {
      envType = "release";
      url = "https://ci-release.vedenemo.dev";
      nodes.testagentHosts = [ "release" ];
      pipelines = [
        "ghaf-hw-test"
        "ghaf-release-candidate"
        "ghaf-release-publish"
      ];
      withGithubStatus = false;
      withGithubWebhook = false;
      withArchiveArtifacts = true;
    };
    auth = {
      clientID = "hetzci-release";
      domain = "ci-release.vedenemo.dev";
    };
    signing.proxy.enable = true;
  };

  # Configure /var/lib/caddy in /etc/fstab for persistent caddy state.
  fileSystems."/var/lib/caddy" = {
    device = "/dev/disk/by-id/scsi-0HC_Volume_103219547";
    fsType = "ext4";
    options = [
      "x-systemd.makefs"
      "x-systemd.growfs"
    ];
  };

  # Ensure only the nixos.org and ghaf-release cachix cache are trusted
  nix.settings.trusted-public-keys = lib.mkForce [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "ghaf-release.cachix.org-1:wvnAftt8aSJ5KukTQb+BvvZYqJ5qzWEk/QHMbn2o+Ag="
  ];
  nix.settings.substituters = lib.mkForce [
    "https://cache.nixos.org/"
    "https://ghaf-release.cachix.org"
  ];
  nix.settings.extra-trusted-public-keys = lib.mkForce [ "" ];
  nix.settings.extra-substituters = lib.mkForce [ "" ];
  nix.settings.trusted-substituters = lib.mkForce [ "" ];
  nix.settings.max-jobs = lib.mkForce 0;
  nix.settings.min-free = lib.mkOverride 60 controllerDisk.minFreeBytes;
  nix.settings.max-free = lib.mkOverride 60 controllerDisk.maxFreeBytes;

  # Configure (release) remote builders
  nix = {
    distributedBuilds = true;
    buildMachines =
      let
        commonOptions = {
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
          commonOptions
          // {
            hostName = "hetz86-rel-2";
            system = "x86_64-linux";
            maxJobs = x86BuilderMaxJobs;
            speedFactor = 12;
            sshUser = "hetz86-rel-2-builder";
            sshKey = "/etc/ssh/certs/hetz86-rel-2-builder";
          }
        )
        (
          commonOptions
          // {
            hostName = "hetzarm-rel-1";
            system = "aarch64-linux";
            maxJobs = armBuilderMaxJobs;
            speedFactor = 2;
            sshUser = "hetzarm-rel-1-builder";
            sshKey = "/etc/ssh/certs/hetzarm-rel-1-builder";
          }
        )
      ];
  };

  programs.ssh = {
    # Known builder host public keys, these go to /root/.ssh/known_hosts
    knownHosts = {
      "hetz86-rel-2".publicKey = machines.hetz86-rel-2.publicKey;
      "${machines.hetz86-rel-2.ip}".publicKey = machines.hetz86-rel-2.publicKey;
      "hetzarm-rel-1".publicKey = machines.hetzarm-rel-1.publicKey;
      "${machines.hetzarm-rel-1.ip}".publicKey = machines.hetzarm-rel-1.publicKey;
    };

    # Custom options to /etc/ssh/ssh_config
    extraConfig = lib.mkAfter ''
      Host hetz86-rel-2
      Hostname ${machines.hetz86-rel-2.ip}
      Host hetzarm-rel-1
      Hostname ${machines.hetzarm-rel-1.ip}
    '';
  };
}
