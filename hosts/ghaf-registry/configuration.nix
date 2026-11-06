# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./disk-config.nix
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    hetzner-cloud
    common
    zot-registry
    openssh
    scheduled-deployment
    team-devenv
  ]);

  sops.defaultSopsFile = ./secrets.yaml;
  system.stateVersion = lib.mkForce "26.05";
  networking.hostName = "ghaf-registry";
  virtualisation.hetzner.withEfiSupport = true;

  services.zot-registry = {
    clientId = "zot-registry";
    domain = "registry.vedenemo.dev";
    metrics.enable = true;
    publicRepositories = [ "ghaf/**" ];
  };

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };

  services.scheduled-deployment = {
    enable = true;
    # Retry for most of the 300 s check budget: after a restart, zot may
    # process its storage before it listens. Anonymous users can read the
    # registry, so the API answers without credentials.
    postDeployChecks = ''
      ${lib.getExe pkgs.curl} -fsS --retry 40 --retry-delay 6 --retry-all-errors -o /dev/null https://registry.vedenemo.dev/v2/
    '';
  };
}
