# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
let
  tuning = import ../../lib/nix-tuning.nix { inherit lib; };

  # Current host sizing: 16 vCPU, 61 GiB RAM, ~1027 GiB /nix disk.
  controllerDisk = tuning.mkDiskThresholds 1027;
in
{
  imports = [
    ./disk-config.nix
    ../common.nix
    ../jenkins.nix
    ../remote-builders.nix
    ../cloud.nix
    ../auth.nix
    ../signing.nix
  ];

  system.stateVersion = lib.mkForce "24.11";
  networking.hostName = "hetzci-dev";
  sops.defaultSopsFile = ./secrets.yaml;

  hetzci = {
    jenkins = {
      envType = "dev";
      url = "https://ci-dev.vedenemo.dev";
      pipelines = [
        "ghaf-hw-test-manual"
        "ghaf-hw-test"
        "ghaf-main"
        "ghaf-manual"
        "ghaf-nightly-perftest"
        "ghaf-nightly-poweroff"
        "ghaf-nightly"
        "ghaf-pre-merge-manual"
        "ghaf-pre-merge"
      ];
    };
    auth = {
      clientID = "hetzci-dev";
      domain = "ci-dev.vedenemo.dev";
    };
    signing.proxy.enable = true;
  };

  nix.settings.max-jobs = lib.mkForce 0;
  nix.settings.min-free = lib.mkOverride 40 controllerDisk.minFreeBytes;
  nix.settings.max-free = lib.mkOverride 40 controllerDisk.maxFreeBytes;
}
