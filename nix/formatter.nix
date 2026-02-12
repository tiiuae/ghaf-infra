# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ ... }:
{
  perSystem =
    { config, pkgs, ... }:
    {
      formatter =
        let
          inherit (config.pre-commit.settings) package configFile;
        in
        pkgs.writeShellScriptBin "pre-commit-run" ''
          set -eu

          # Run all hooks except pylint first, then lint only changed Python files.
          SKIP=pylint ${pkgs.lib.getExe package} run --all-files --config ${configFile}

          if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            echo "pylint: skipped (not in a git work tree)"
            exit 0
          fi

          mapfile -t py_files < <(
            {
              git diff --name-only --diff-filter=ACMR -- "*.py"
              git diff --cached --name-only --diff-filter=ACMR -- "*.py"
              git ls-files --others --exclude-standard -- "*.py"
            } | sort -u
          )

          if [ "''${#py_files[@]}" -eq 0 ]; then
            echo "pylint: skipped (no changed Python files)"
            exit 0
          fi

          echo "pylint: running on ''${#py_files[@]} changed Python file(s)"
          ${pkgs.lib.getExe package} run pylint --config ${configFile} --files "''${py_files[@]}"
        '';
    };
}
