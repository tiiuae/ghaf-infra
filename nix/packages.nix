# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  inputs,
  ...
}:
{
  perSystem =
    { pkgs, self', ... }:
    {
      packages = {
        policy-checker = pkgs.callPackage ../pkgs/policy-checker {
          selfPkgs = self'.packages;
        };
        nethsm-exporter = pkgs.callPackage ../pkgs/nethsm-exporter { };
        oci-publish = pkgs.callPackage ../pkgs/oci-publish { };
        pkcs11-proxy = pkgs.callPackage ../pkgs/pkcs11-proxy { };
        systemd-sbsign = pkgs.callPackage ../pkgs/systemd-sbsign { };
        nethsm-pkcs11 = pkgs.callPackage ../pkgs/nethsm-pkcs11 { };
        softhsm2 = pkgs.callPackage ../pkgs/softhsm2 { };
        zot = pkgs.callPackage ../pkgs/zot { };

        # Vendored in as nixos-25.11 has outdated package,
        # which doesn't include the frontend assets
        fleet = pkgs.callPackage ../pkgs/fleet { };
        fleetctl = pkgs.fleetctl.override {
          inherit (self'.packages) fleet;
        };

        # Vendored in, as brainstem isn't suitable for nixpkgs packaging upstream:
        # https://github.com/NixOS/nixpkgs/pull/313643
        brainstem = pkgs.callPackage ../pkgs/brainstem {
          ciTestAutomationSrc = inputs.robot-framework.outPath;
        };
      };
    };
}
