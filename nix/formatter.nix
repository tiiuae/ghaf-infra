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
          ${pkgs.lib.getExe package} run --all-files --config ${configFile}
        '';
    };
}
