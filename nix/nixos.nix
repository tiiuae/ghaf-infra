# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  flake-parts-lib,
  ...
}: let
  inherit (config) systems allSystems;
in {
  options.perSystem = flake-parts-lib.mkPerSystemOption {
    options.nixosConfigurations = with lib;
      mkOption {
        description = "define nixosConfigurations in a perSystem function";
        type = types.lazyAttrsOf types.unspecified;
        default = {};
      };
  };

  config = {
    flake = {
      nixosConfigurations = with lib;
        builtins.foldl'
        (x: y: x // y) {}
        (attrValues (genAttrs systems (system: allSystems.${system}.nixosConfigurations)));
    };
  };
}
