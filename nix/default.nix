# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, self, ... }:
{
  options.flake.lib = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
  };

  # Target sets consumed by .github/workflows/test-ghaf-infra.yml.
  config.flake.lib.ciBuilds = lib.mapAttrs (
    system: hosts:
    {
      nixosConfigurations = lib.genAttrs hosts (
        host: self.nixosConfigurations.${host}.config.system.build.toplevel
      );
    }
    // lib.optionalAttrs (system == "x86_64-linux") {
      devShells = self.devShells.${system};
      checks.pre-commit = self.checks.${system}.pre-commit;
    }
  ) self.lib.hostsBySystem;

  imports = [
    ./apps.nix
    ./deployments.nix
    ./devshell.nix
    ./git-hooks.nix
    ./packages.nix
    ./formatter.nix
  ];
}
