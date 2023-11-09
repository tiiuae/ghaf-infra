# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
_: {
  perSystem = {pkgs, ...}: {
    checks = {
      reuse =
        pkgs.runCommandLocal "reuse-lint" {
          buildInputs = [pkgs.reuse];
        } ''
          cd ${../.}
          reuse lint
          touch $out
        '';
    };
  };
}
