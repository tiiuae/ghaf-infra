# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        policy-checker = pkgs.callPackage ../pkgs/policy-checker { };
      };
    };
}
