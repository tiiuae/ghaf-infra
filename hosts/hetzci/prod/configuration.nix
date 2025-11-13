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
      casc = ./casc;
      pluginsFile = ./plugins.json;
      withCachix = false;
    };
    auth = {
      clientID = "hetzci-prod";
      domain = "ci-prod.vedenemo.dev";
    };
    signing.proxy.enable = true;
  };
}
