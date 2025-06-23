# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  ...
}:
let
  inherit (inputs) deploy-rs;

  mkDeployment = arch: config: ip: {
    hostname = ip;
    inherit config; # used for installation script
    profiles.system = {
      user = "root";
      path = deploy-rs.lib.${arch}.activate.nixos self.nixosConfigurations.${config};
    };
  };

  x86-nodes = {
    build1 = mkDeployment "x86_64-linux" "build1" "172.18.20.102";
    build2 = mkDeployment "x86_64-linux" "build2" "172.18.20.103";
    build3 = mkDeployment "x86_64-linux" "build3" "172.18.20.104";
    build4 = mkDeployment "x86_64-linux" "build4" "172.18.20.105";
    himalia = mkDeployment "x86_64-linux" "himalia" "172.18.20.106";
    monitoring = mkDeployment "x86_64-linux" "monitoring" "172.18.20.108";
    binarycache = mkDeployment "x86_64-linux" "binarycache" "172.18.20.109";
    testagent-prod = mkDeployment "x86_64-linux" "testagent-prod" "172.18.16.60";
    testagent-dev = mkDeployment "x86_64-linux" "testagent-dev" "172.18.16.33";
    testagent-release = mkDeployment "x86_64-linux" "testagent-release" "172.18.16.32";
    ghaf-log = mkDeployment "x86_64-linux" "ghaf-log" "95.217.177.197";
    ghaf-coverity = mkDeployment "x86_64-linux" "ghaf-coverity" "135.181.103.32";
    ghaf-proxy = mkDeployment "x86_64-linux" "ghaf-proxy" "95.216.200.85";
    ghaf-webserver = mkDeployment "x86_64-linux" "ghaf-webserver" "37.27.204.82";
    ghaf-auth = mkDeployment "x86_64-linux" "ghaf-auth" "37.27.190.109";
    testagent-uae-dev = mkDeployment "x86_64-linux" "testagent-uae-dev" "172.19.16.12";
    hetzci-prod = mkDeployment "x86_64-linux" "hetzci-prod" "157.180.43.236";
    hetzci-dev = mkDeployment "x86_64-linux" "hetzci-dev" "157.180.119.138";
    hetz86-1 = mkDeployment "x86_64-linux" "hetz86-1" "37.27.170.242";
    hetz86-builder = mkDeployment "x86_64-linux" "hetz86-builder" "65.108.7.79";
  };

  aarch64-nodes = {
    hetzarm = mkDeployment "aarch64-linux" "hetzarm" "65.21.20.242";
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
