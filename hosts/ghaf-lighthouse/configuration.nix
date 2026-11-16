# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  pkgs,
  config,
  machines,
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
    openssh
    nebula
    scheduled-deployment
    team-devenv
  ]);

  sops.defaultSopsFile = ./secrets.yaml;

  system.stateVersion = lib.mkForce "25.05";
  networking.hostName = "ghaf-lighthouse";

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };

  services.scheduled-deployment = {
    enable = true;
    # Nebula seeds its own DNS record, so this works without waiting for peers
    # to re-register after a restart. Use the actual certificate name.
    postDeployChecks = ''
      dns_name=$(${
        lib.getExe' config.services.nebula.networks.${config.nebula.networkName}.package "nebula-cert"
      } print -json -path ${config.sops.secrets.nebula-cert.path} | ${lib.getExe pkgs.jq} -er '.[0].details.name')
      for attempt in {1..10}; do
        if ${lib.getExe' pkgs.dig "dig"} @127.0.0.1 "$dns_name." A +short +time=2 +tries=1 | ${lib.getExe pkgs.gnugrep} -Fx '${machines.ghaf-lighthouse.nebula_ip}'; then
          break
        fi
        if [[ $attempt == 10 ]]; then
          echo 'Lighthouse DNS did not return its Nebula address' >&2
          exit 1
        fi
        sleep 6
      done
    '';
  };

  nebula = {
    enable = true;
    isLighthouse = true;
  };
}
