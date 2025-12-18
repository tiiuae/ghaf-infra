# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
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
}
