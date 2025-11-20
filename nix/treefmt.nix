# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
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
          shellcheck.enable = true; # bash linter https://github.com/koalaman/shellcheck
          shfmt.enable = true; # bash formatter https://github.com/mvdan/sh
          ruff-format.enable = true; # python formatter https://github.com/astral-sh/ruff
          actionlint.enable = true; # github actions linter
        };
      };

      formatter = config.treefmt.build.wrapper;
    };
}
