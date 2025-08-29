# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  machines,
  config,
  lib,
  ...
}:
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
          maxJobs = 20;
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
          }
          // commonOptions
        )
        (
          {
            hostName = "hetz86-1.vedenemo.dev";
            system = "x86_64-linux";
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
