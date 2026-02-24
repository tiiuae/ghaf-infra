# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  machines,
  config,
  lib,
  ...
}:
let
  tuning = import ../lib/nix-tuning.nix { inherit lib; };

  # Current shared builder sizing:
  # - hetz86-1: 96 vCPU, 251 GiB RAM
  # - hetzarm: 80 vCPU, 250 GiB RAM
  x86BuilderMaxJobs = tuning.mkMaxJobs {
    cpus = 96;
    ramGiB = 251;
  };
  armBuilderMaxJobs = tuning.mkMaxJobs {
    cpus = 80;
    ramGiB = 250;
  };
in
{
  sops = {
    secrets = {
      vedenemo_builder_ssh_key.owner = "root";
    };
  };

  nix = {
    distributedBuilds = true;
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
            hostName = "hetzarm.vedenemo.dev";
            system = "aarch64-linux";
            maxJobs = armBuilderMaxJobs;
          }
          // commonOptions
        )
        (
          {
            hostName = "hetz86-1.vedenemo.dev";
            system = "x86_64-linux";
            maxJobs = x86BuilderMaxJobs;
          }
          // commonOptions
        )
      ];
  };

  programs.ssh = {
    # Known builder host public keys, these go to /root/.ssh/known_hosts
    knownHosts = {
      "hetz86-1.vedenemo.dev".publicKey = machines.hetz86-1.publicKey;
      "hetzarm.vedenemo.dev".publicKey = machines.hetzarm.publicKey;
    };

    # Custom options to /etc/ssh/ssh_config
    extraConfig = lib.mkAfter ''
      Host hetz86-1.vedenemo.dev
      Hostname hetz86-1.vedenemo.dev
      User remote-build
      IdentityFile ${config.sops.secrets.vedenemo_builder_ssh_key.path}

      Host hetzarm.vedenemo.dev
      Hostname hetzarm.vedenemo.dev
      User remote-build
      IdentityFile ${config.sops.secrets.vedenemo_builder_ssh_key.path}
    '';
  };
}
