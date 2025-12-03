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
  networking.hostName = "hetzci-prod";
  sops.defaultSopsFile = ./secrets.yaml;

  hetzci = {
    jenkins = {
      envType = "prod";
      pluginsFile = ./plugins.json;
      url = "https://ci-prod.vedenemo.dev";
      pipelines = [
        "ghaf-hw-test-manual"
        "ghaf-hw-test"
        "ghaf-main"
        "ghaf-manual"
        "ghaf-nightly-perftest"
        "ghaf-nightly"
        "ghaf-pre-merge-manual"
        "ghaf-pre-merge"
      ];
      withCachix = false;
    };
    auth = {
      clientID = "hetzci-prod";
      domain = "ci-prod.vedenemo.dev";
    };
    signing.proxy.enable = true;
  };
}
