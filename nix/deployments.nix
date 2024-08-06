# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  ...
}: let
  inherit (inputs) deploy-rs;

  mkDeployment = arch: config: hostname: {
    inherit hostname;
    profiles.system = {
      user = "root";
      path = deploy-rs.lib.${arch}.activate.nixos self.nixosConfigurations.${config};
    };
  };

  x86-nodes = {
    build3 = mkDeployment "x86_64-linux" "build3" "172.18.20.104";
    build4 = mkDeployment "x86_64-linux" "build4" "172.18.20.105";
    himalia = mkDeployment "x86_64-linux" "himalia" "172.18.20.106";
    monitoring = mkDeployment "x86_64-linux" "monitoring" "172.18.20.108";
    binarycache = mkDeployment "x86_64-linux" "binarycache" "172.18.20.109";
    testagent = mkDeployment "x86_64-linux" "testagent" "172.18.16.60";
    ghaf-log = mkDeployment "x86_64-linux" "ghaf-log" "95.217.177.197";
  };

  aarch64-nodes = {
    hetzarm = mkDeployment "aarch64-linux" "hetzarm" "65.21.20.242";
  };
in {
  flake = {
    deploy.nodes = x86-nodes // aarch64-nodes;

    checks = {
      x86_64-linux = deploy-rs.lib.x86_64-linux.deployChecks {nodes = x86-nodes;};
      aarch64-linux = deploy-rs.lib.aarch64-linux.deployChecks {nodes = aarch64-nodes;};
    };
  };
}
