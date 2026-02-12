# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, self, ... }:
{
  imports = with inputs; [
    git-hooks-nix.flakeModule
  ];
  perSystem =
    { pkgs, ... }:
    {
      # See https://flake.parts/options/pre-commit-hooks-nix
      # for all the available hooks and options
      pre-commit = {
        settings.hooks = {
          # lint commit messages
          gitlint.enable = true;
          # fix end-of-files
          end-of-file-fixer.enable = true;
          # trim trailing whitespaces
          trim-trailing-whitespace.enable = true;
          # spell check
          typos = {
            enable = true;
            excludes = [
              "^LICENSES/.*"
              ".*\.yaml"
              ".*\.crypt"
              ".*/plugins\.json"
            ];
            settings = {
              configPath = "${self.outPath}/.typos.toml";
            };
          };
          # check reuse compliance
          reuse.enable = true;
          # nix formatter
          nixfmt.enable = true;
          # removes dead nix code
          deadnix.enable = true;
          # prevents use of nix anti-patterns
          statix = {
            enable = true;
            args = [
              "fix"
            ];
          };
          # bash linter
          shellcheck.enable = true;
          # bash formatter
          shfmt = {
            enable = true;
            args = [
              "--indent"
              "2"
            ];
          };
          # python formatter
          ruff-format.enable = true;
          # github actions linter
          actionlint.enable = true;
          # python linter
          pylint = {
            enable = true;
            args = [
              "--jobs=0"
              "--enable=useless-suppression"
              "--fail-on=useless-suppression"
            ];
            package = (
              pkgs.python3.withPackages (
                pp: with pp; [
                  aiohttp
                  deploykit
                  invoke
                  loguru
                  prometheus-client
                  pycodestyle
                  pylint
                  requests
                  tabulate
                  urllib3
                ]
              )
            );
          };
        };
      };
    };
}
