# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
_: {
  perSystem =
    { pkgs, ... }:
    {
      checks = {
        reuse = pkgs.runCommandLocal "reuse-lint" { buildInputs = [ pkgs.reuse ]; } ''
          cd ${../.}
          reuse lint
          touch $out
        '';
        pycodestyle =
          pkgs.runCommandLocal "pycodestyle" { nativeBuildInputs = [ pkgs.python3.pkgs.pycodestyle ]; }
            ''
              cd ${../.}
              pycodestyle --max-line-length 90 $(find . -type f -name "*.py" ! -path "*result*" ! -path "*eggs*")
              touch $out
            '';
        pylint =
          pkgs.runCommandLocal "pylint"
            {
              nativeBuildInputs = with pkgs.python3.pkgs; [
                pylint
                colorlog
                deploykit
                invoke
                tabulate
              ];
            }
            ''
              cd ${../.}
              export HOME=/tmp
              pylint --enable=useless-suppression -rn $(find . -type f -name "*.py" ! -path "*result*" ! -path "*eggs*")
              touch $out
            '';
        black = pkgs.runCommandLocal "black" { nativeBuildInputs = [ pkgs.python3.pkgs.black ]; } ''
          cd ${../.}
          black -q $(find . -type f -name "*.py" ! -path "*result*" ! -path "*eggs*")
          touch $out
        '';
      };
    };
}
