# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ self, inputs, ... }: {
    flake.nixosModules = {
        common = ./common;
        azure = ./environment/azure.nix;
        hetzner-cloud = ./environment/hetzner-cloud.nix;
        hetzner-robot = ./environment/hetzner-robot.nix;
        zot-registry = ./zot-registry.nix;
        zramSwap = ./zramswap.nix;
        nginx = ./nginx.nix;
        monitoring = ./monitoring.nix;
        jenkins = import ./jenkins { inherit self inputs; };
        testagent = import ./testagent { inherit self inputs; };
        openssh = ./openssh.nix;
        nebula = ./nebula;
    };
}
