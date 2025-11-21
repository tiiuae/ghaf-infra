# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, self, ... }:
{
  imports = with inputs; [
    git-hooks-nix.flakeModule
  ];
  perSystem =
    { pkgs, ... }:
    let
      typosConfig = pkgs.writeText "typos.toml" ''
        [default]
        extend-ignore-re = [
          ".*ssh-ed25519 .*",
          ".*aks-uaenorth.*",
          ".*set -ue.*",
        ]
      '';
    in
    {
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
              configPath = typosConfig.outPath;
            };
          };
          # check reuse compliance
          reuse.enable = true;
          # run all formatters
          treefmt = {
            package = self.formatter.${pkgs.system};
            enable = true;
          };
        };
      };
    };
}
