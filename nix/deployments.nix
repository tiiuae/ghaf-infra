# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
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
    build1 = mkDeployment "build1" machines.build1.ip;
    build2 = mkDeployment "build2" machines.build2.ip;
    build3 = mkDeployment "build3" machines.build3.ip;
    build4 = mkDeployment "build4" machines.build4.ip;
    monitoring = mkDeployment "monitoring" machines.monitoring.ip;
    binarycache = mkDeployment "binarycache" machines.binarycache.ip;
    testagent-prod = mkDeployment "testagent-prod" machines.testagent-prod.ip;
    testagent-dev = mkDeployment "testagent-dev" machines.testagent-dev.ip;
    testagent-release = mkDeployment "testagent-release" machines.testagent-release.ip;
    testagent-uae-dev = mkDeployment "testagent-uae-dev" machines.testagent-uae-dev.ip;
    ghaf-log = mkDeployment "ghaf-log" machines.ghaf-log.ip;
    ghaf-coverity = mkDeployment "ghaf-coverity" machines.ghaf-coverity.ip;
    ghaf-proxy = mkDeployment "ghaf-proxy" machines.ghaf-proxy.ip;
    ghaf-webserver = mkDeployment "ghaf-webserver" machines.ghaf-webserver.ip;
    ghaf-auth = mkDeployment "ghaf-auth" machines.ghaf-auth.ip;
    hetzci-prod = mkDeployment "hetzci-prod" machines.hetzci-prod.ip;
    hetzci-dev = mkDeployment "hetzci-dev" machines.hetzci-dev.ip;
    hetz86-1 = mkDeployment "hetz86-1" machines.hetz86-1.ip;
    hetz86-builder = mkDeployment "hetz86-builder" machines.hetz86-builder.ip;
  };

  aarch64-nodes = {
    hetzarm = mkDeployment "hetzarm" machines.hetzarm.ip;
  };
in
{
  flake = {
    deploy =
      let
        nodes = x86-nodes // aarch64-nodes;
      in
      {
        inherit nodes;
        targets = lib.attrsets.mapAttrs (
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

    checks = {
      x86_64-linux = deploy-rs.lib.x86_64-linux.deployChecks { nodes = x86-nodes; };
      aarch64-linux = deploy-rs.lib.aarch64-linux.deployChecks { nodes = aarch64-nodes; };
    };
  };
}
