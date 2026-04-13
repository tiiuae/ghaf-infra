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
      # Stubbed Jenkins specific classes so they don't prevent groovy from compiling
      # Add more classes here if they block compilation
      jenkins-groovy-stubs = pkgs.symlinkJoin {
        name = "jenkins-groovy-stubs-src";
        paths = [
          (pkgs.writeTextDir "NonCPS.groovy" ''
            @interface NonCPS {}
          '')
          (pkgs.writeTextDir "org/jenkinsci/plugins/pipeline/modeldefinition/Utils.groovy" ''
            package org.jenkinsci.plugins.pipeline.modeldefinition

            class Utils {
              static void markStageSkippedForConditional(String stageName) {}
            }
          '')
        ];
      };

      jenkins-groovy =
        pkgs.runCommand "jenkins-groovy-stubs"
          {
            nativeBuildInputs = [
              pkgs.groovy
            ];
          }
          ''
            mkdir -p "$out"
            groovyc -d "$out" $(find ${jenkins-groovy-stubs} -name '*.groovy' -print)
          '';

      groovyc-check = pkgs.writeShellApplication {
        name = "groovyc-check";
        runtimeInputs = [
          pkgs.groovy
        ];
        text = ''
          tmpdir="$(mktemp -d)"
          trap 'rm -rf "$tmpdir"' EXIT
          exec groovyc --classpath "${jenkins-groovy}" -d "$tmpdir" "$@"
        '';
      };

      python-env = pkgs.python3.withPackages (
        pp: with pp; [
          aiohttp
          deploykit
          invoke
          loguru
          prometheus-client
          pycodestyle
          pytest
          pylint
          requests
          tabulate
          urllib3
        ]
      );
    in
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
          pytest-tasks = {
            enable = true;
            name = "pytest-tasks";
            entry = "${pkgs.lib.getExe' python-env "pytest"} -q tests/test_tasks.py";
            files = "^(tasks\\.py|tests/test_tasks\\.py)$";
            pass_filenames = false;
          };
          # github actions linter
          actionlint.enable = true;
          # python linter
          pylint = {
            enable = true;
            args = [
              "--init-hook=import sys; sys.path.insert(0, \".\")"
              "--jobs=0"
              "--enable=useless-suppression"
              "--fail-on=useless-suppression"
            ];
            package = python-env;
          };
          groovyc = {
            enable = true;
            name = "groovyc";
            entry = "${pkgs.lib.getExe groovyc-check}";
            files = "^hosts/hetzci/pipelines/.*\\.groovy$";
          };
        };
      };
    };
}
