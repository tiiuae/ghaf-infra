# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        policy-checker = pkgs.callPackage ../pkgs/policy-checker { };
        sshified = pkgs.callPackage ../pkgs/sshified { };

        # Vendored in, as brainstem isn't suitable for nixpkgs packaging upstream:
        # https://github.com/NixOS/nixpkgs/pull/313643
        brainstem = pkgs.callPackage ../pkgs/brainstem { };
      };
    };
}
