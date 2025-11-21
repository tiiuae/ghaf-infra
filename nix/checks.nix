# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks = {
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
                prometheus-client
                urllib3
                requests
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
