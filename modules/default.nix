# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  flake.nixosModules = {
    common = ./common;
    azure = ./environment/azure.nix;
    hetzner-cloud = ./environment/hetzner-cloud.nix;
    hetzner-robot = ./environment/hetzner-robot.nix;
    zot-registry = ./zot-registry.nix;
    zramSwap = ./zramswap.nix;
  };
}
