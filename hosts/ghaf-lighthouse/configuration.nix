# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  config,
  inputs,
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
    service-nebula
    team-devenv
  ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      nebula-cert.owner = config.nebula.user;
      nebula-key.owner = config.nebula.user;
    };
  };

  system.stateVersion = lib.mkForce "25.05";
  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "ghaf-lighthouse";

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };

  nebula = {
    enable = true;
    isLighthouse = true;
    cert = config.sops.secrets.nebula-cert.path;
    key = config.sops.secrets.nebula-key.path;
  };
}
