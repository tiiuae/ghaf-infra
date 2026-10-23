# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  config,
  machines,
  lib,
  ...
}:
let
  tuning = import ../../lib/nix-tuning.nix { inherit lib; };

  # Current hetzarm sizing: 80 vCPU, 250 GiB RAM.
  armBuilder = tuning.mkBuildLimits {
    cpus = 80;
    ramGiB = 250;
  };
in
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
      ssh_private_key.owner = "root";
    };
  };

  system.stateVersion = "23.11";
  networking.hostName = "hetz86-builder";
  boot.kernelModules = [ "kvm-amd" ];

  builder = {
    enable = true;
    sshPublicKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM2rhqSdifRmTwyrc3rvXWyDMznrIAAkVwhEsufLYiTp"
    ];
    crossCompilation.enable = true;
    # Tuning is disabled on this builder
    tuning.enable = false;
  };

  services.monitoring = {
    metrics = {
      enable = true;
      ssh = true;
    };
    logs.enable = true;
  };

  # use hetzarm as aarch64 remote builder
  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "hetzarm.vedenemo.dev";
        system = "aarch64-linux";
        maxJobs = armBuilder.maxJobs;
        speedFactor = 1;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
        mandatoryFeatures = [ ];
        sshUser = "hetz86-builder";
        sshKey = config.sops.secrets.ssh_private_key.path;
      }
    ];
  };

  programs.ssh.knownHosts = {
    "hetzarm.vedenemo.dev".publicKey = machines.hetzarm.publicKey;
  };
}
