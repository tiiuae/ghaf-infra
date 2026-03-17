# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  machines,
  config,
  lib,
  ...
}:
let
  tuning = import ../../lib/nix-tuning.nix { inherit lib; };

  # Current shared builder sizing:
  # - az86-1: 32 vCPU, 128 GiB RAM
  # - hetzarm-1: 16 vCPU, 32 GiB RAM
  x86BuilderMaxJobs = tuning.mkMaxJobs {
    cpus = 32;
    ramGiB = 128;
  };
  armBuilderMaxJobs = tuning.mkMaxJobs {
    cpus = 16;
    ramGiB = 32;
  };
in
{
  sops = {
    secrets = {
      azureci_builder_ssh_key.owner = "root";
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
            hostName = "az86-1.uaenorth.cloudapp.azure.com";
            system = "x86_64-linux";
            maxJobs = x86BuilderMaxJobs;
          }
          // commonOptions
        )
        (
          {
            hostName = "91.98.90.243";
            system = "aarch64-linux";
            maxJobs = armBuilderMaxJobs;
          }
          // commonOptions
        )
      ];
  };

  programs.ssh = {
    # Known builder host public keys, these go to /root/.ssh/known_hosts
    knownHosts = {
      "az86-1.uaenorth.cloudapp.azure.com".publicKey = machines.uae-azureci-az86-1.publicKey;
      "91.98.90.243".publicKey = machines.uae-azureci-hetzarm-1.publicKey;
    };

    # Custom options to /etc/ssh/ssh_config
    extraConfig = lib.mkAfter ''
      Host az86-1.uaenorth.cloudapp.azure.com
      Hostname az86-1.uaenorth.cloudapp.azure.com
      User uae-remote-build
      IdentityFile ${config.sops.secrets.azureci_builder_ssh_key.path}

      Host 91.98.90.243
      Hostname 91.98.90.243
      User uae-remote-build
      IdentityFile ${config.sops.secrets.azureci_builder_ssh_key.path}
    '';
  };
}
