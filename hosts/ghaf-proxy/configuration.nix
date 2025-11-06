# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  inputs,
  lib,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ../hetzner-cloud.nix
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    team-devenv
    user-bmg
    user-flokli
  ]);

  system.stateVersion = lib.mkForce "24.05";
  nixpkgs.hostPlatform = "x86_64-linux";

  sops.defaultSopsFile = ./secrets.yaml;

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };

  networking.hostName = "ghaf-proxy";

  environment.systemPackages = with pkgs; [
    screen
    tmux
    azure-cli
    dnsutils
    inetutils
    openssl
  ];
}
