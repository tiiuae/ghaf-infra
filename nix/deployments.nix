# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  ...
}:
let
  hostInventory = import ../hosts/machines.nix;
  isDeployableHost = host: host ? machine;

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

  mkNodesFor =
    system:
    lib.mapAttrs (name: host: mkDeployment name host.machine.ip) (
      lib.filterAttrs (_: host: isDeployableHost host && host.system == system) hostInventory
    );

  x86-nodes = mkNodesFor "x86_64-linux";
  aarch64-nodes = mkNodesFor "aarch64-linux";

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
