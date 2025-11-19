# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  ...
}:
let
  machines = import ../hosts/machines.nix;

  inherit (inputs) deploy-rs;

  mkDeployment = config: ip: {
    hostname = ip;
    inherit config; # used for installation script
    profiles.system =
      let
        cfg = self.nixosConfigurations.${config};
      in
      {
        user = "root";
        path = deploy-rs.lib.${cfg.config.nixpkgs.hostPlatform.system}.activate.nixos cfg;
      };
  };

  x86-nodes = {
    testagent-prod = mkDeployment "testagent-prod" machines.testagent-prod.ip;
    testagent-dev = mkDeployment "testagent-dev" machines.testagent-dev.ip;
    testagent2-prod = mkDeployment "testagent2-prod" machines.testagent2-prod.ip;
    testagent-release = mkDeployment "testagent-release" machines.testagent-release.ip;
    testagent-uae-dev = mkDeployment "testagent-uae-dev" machines.testagent-uae-dev.ip;
    nethsm-gateway = mkDeployment "nethsm-gateway" machines.nethsm-gateway.ip;
    ghaf-log = mkDeployment "ghaf-log" machines.ghaf-log.ip;
    ghaf-proxy = mkDeployment "ghaf-proxy" machines.ghaf-proxy.ip;
    ghaf-webserver = mkDeployment "ghaf-webserver" machines.ghaf-webserver.ip;
    ghaf-auth = mkDeployment "ghaf-auth" machines.ghaf-auth.ip;
    ghaf-monitoring = mkDeployment "ghaf-monitoring" machines.ghaf-monitoring.ip;
    ghaf-lighthouse = mkDeployment "ghaf-lighthouse" machines.ghaf-lighthouse.ip;
    ghaf-fleetdm = mkDeployment "ghaf-fleetdm" machines.ghaf-fleetdm.ip;
    hetzci-release = mkDeployment "hetzci-release" machines.hetzci-release.ip;
    hetzci-prod = mkDeployment "hetzci-prod" machines.hetzci-prod.ip;
    hetzci-dev = mkDeployment "hetzci-dev" machines.hetzci-dev.ip;
    hetz86-1 = mkDeployment "hetz86-1" machines.hetz86-1.ip;
    hetz86-builder = mkDeployment "hetz86-builder" machines.hetz86-builder.ip;
    hetz86-rel-1 = mkDeployment "hetz86-rel-1" machines.hetz86-rel-1.ip;
    uae-lab-node1 = mkDeployment "uae-lab-node1" machines.uae-lab-node1.ip;
    uae-nethsm-gateway = mkDeployment "uae-nethsm-gateway" machines.uae-nethsm-gateway.ip;
    uae-azure-vm1 = mkDeployment "uae-azure-vm1" machines.uae-azure-vm1.ip;
  };

  aarch64-nodes = {
    hetzarm = mkDeployment "hetzarm" machines.hetzarm.ip;
    hetzarm-rel-1 = mkDeployment "hetzarm-rel-1" machines.hetzarm-rel-1.ip;
  };

  nodes = x86-nodes // aarch64-nodes;
in
{
  flake = {
    deploy = { inherit nodes; };

    checks = {
      x86_64-linux = deploy-rs.lib.x86_64-linux.deployChecks { nodes = x86-nodes; };
      aarch64-linux = deploy-rs.lib.aarch64-linux.deployChecks { nodes = aarch64-nodes; };
    };

    # used by tasks.py
    installationTargets = lib.attrsets.mapAttrs (
      _: node:
      let
        cnf = self.nixosConfigurations.${node.config}.config;
      in
      {
        inherit (node) hostname config;
        secrets =
          if (lib.attrsets.hasAttrByPath [ "sops" "defaultSopsFile" ] cnf) then
            cnf.sops.defaultSopsFile
          else
            null;
      }
    ) nodes;
  };
}
