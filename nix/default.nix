# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
{
  options.flake.lib = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
  };

  imports = [
    ./apps.nix
    ./deployments.nix
    ./devshell.nix
    ./git-hooks.nix
    ./packages.nix
    ./formatter.nix
  ];
}
