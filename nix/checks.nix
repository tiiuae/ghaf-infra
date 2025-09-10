# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks = {
        reuse = pkgs.runCommandLocal "reuse-lint" { buildInputs = [ pkgs.reuse ]; } ''
          cd ${self.outPath}
          reuse lint
          touch $out
        '';
        pycodestyle =
          pkgs.runCommandLocal "pycodestyle" { nativeBuildInputs = [ pkgs.python3.pkgs.pycodestyle ]; }
            ''
              cd ${self.outPath}
              pycodestyle --max-line-length 90 $(find . -type f -name "*.py" ! -path "*result*" ! -path "*eggs*")
              touch $out
            '';
        pylint =
          pkgs.runCommandLocal "pylint"
            {
              nativeBuildInputs = with pkgs.python3.pkgs; [
                pylint
                deploykit
                invoke
                tabulate
                aiohttp
                loguru
              ];
            }
            ''
              cd ${self.outPath}
              export HOME=/tmp
              pylint --enable=useless-suppression -rn $(find . -type f -name "*.py" ! -path "*result*" ! -path "*eggs*")
              touch $out
            '';
      };
    };
}
