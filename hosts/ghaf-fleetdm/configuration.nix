# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disk-config.nix
    ./fleet.nix
  ]
  ++ (with self.nixosModules; [
    hetzner-cloud
    common
    openssh
    nginx
    scheduled-deployment
    team-devenv
    user-vadikas
  ]);

  networking.hostName = "ghaf-fleetdm";
  system.stateVersion = lib.mkForce "25.05";
  sops.defaultSopsFile = ./secrets.yaml;

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };

  services.scheduled-deployment = {
    enable = true;
    # Retry while the services restarted by a switch start up. Fleet's health
    # check, through nginx, also covers MySQL and Redis.
    postDeployChecks = ''
      ${lib.getExe pkgs.curl} -fsS --retry 10 --retry-delay 6 --retry-all-errors -o /dev/null https://fleetdm.vedenemo.dev/healthz
    '';
  };
}
