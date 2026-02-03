# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  machines,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ../common.nix
    ../jenkins.nix
    ../auth.nix
    ../../hetzner-cloud.nix
  ];

  system.stateVersion = lib.mkForce "25.11";
  networking.hostName = "hetzci-dbg";

  hetzci = {
    jenkins = {
      envType = "dev";
      url = "https://ci-dbg.vedenemo.dev";
      pipelines = [
        "ghaf-hw-test"
        "ghaf-release-candidate"
      ];
      withCachix = false;
      withGithubStatus = false;
      withGithubWebhook = false;
    };
    auth = {
      clientID = "hetzci-dbg";
      domain = "ci-dbg.vedenemo.dev";
    };
  };

  sops = {
    defaultSopsFile = ./secrets.yaml;
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
            hostName = machines.hetzarm-dbg-1.ip;
            system = "aarch64-linux";
          }
          // commonOptions
        )
        (
          {
            hostName = machines.hetz86-dbg-1.ip;
            system = "x86_64-linux";
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
