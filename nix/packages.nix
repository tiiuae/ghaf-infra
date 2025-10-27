# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        policy-checker = pkgs.callPackage ../pkgs/policy-checker { };
        nethsm-exporter = pkgs.callPackage ../pkgs/nethsm-exporter { };
        pkcs11-proxy = pkgs.callPackage ../pkgs/pkcs11-proxy { };
        systemd-sbsign = pkgs.callPackage ../pkgs/systemd-sbsign { };
        nethsm-pkcs11 = pkgs.callPackage ../pkgs/nethsm-pkcs11 { };
        softhsm2 = pkgs.callPackage ../pkgs/softhsm2 { };

        # Vendored in, as brainstem isn't suitable for nixpkgs packaging upstream:
        # https://github.com/NixOS/nixpkgs/pull/313643
        brainstem = pkgs.callPackage ../pkgs/brainstem { };
      };
    };
}
