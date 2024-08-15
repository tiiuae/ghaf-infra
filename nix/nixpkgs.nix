# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      # customise pkgs
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system inputs;
        config = {
          # required to use terraform
          allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "terraform" ];
        };
      };
      # make custom top-level lib available to all `perSystem` functions
      _module.args.lib = lib;
    };
}
