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
      azureci_builder_ssh_key.owner = "root";
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
            hostName = "az86-1.uaenorth.cloudapp.azure.com";
            system = "x86_64-linux";
          }
          // commonOptions
        )
      ];
  };

  programs.ssh = {
    # Known builder host public keys, these go to /root/.ssh/known_hosts
    knownHosts = {
      "az86-1.uaenorth.cloudapp.azure.com".publicKey = machines.uae-azureci-az86-1.publicKey;
    };

    # Custom options to /etc/ssh/ssh_config
    extraConfig = lib.mkAfter ''
      Host az86-1.uaenorth.cloudapp.azure.com
      Hostname az86-1.uaenorth.cloudapp.azure.com
      User uae-remote-build
      IdentityFile ${config.sops.secrets.azureci_builder_ssh_key.path}
    '';
  };
}
