# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  imports = with inputs; [
    flake-root.flakeModule
    treefmt-nix.flakeModule
  ];
  perSystem =
    { config, ... }:
    {
      treefmt.config = {
        inherit (config.flake-root) projectRootFile;

        settings.global.excludes = [
          "*.md"
          "*.txt"
          "*.png"
        ];

        programs = {
          nixfmt.enable = true; # nix formatter (rfc-style) https://github.com/NixOS/nixfmt
          deadnix.enable = true; # removes dead nix code https://github.com/astro/deadnix
          statix.enable = true; # prevents use of nix anti-patterns https://github.com/nerdypepper/statix
          shellcheck.enable = true; # lints shell scripts https://github.com/koalaman/shellcheck
          ruff-format.enable = true; # faster python formatter which is equivalent to black
          terraform.enable = true; # terraform formatter
          actionlint.enable = true; # lints github actions
        };
      };

      formatter = config.treefmt.build.wrapper;
    };
}
