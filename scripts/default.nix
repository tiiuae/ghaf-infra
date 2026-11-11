# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ self, inputs, ... }:
{
  flake.lib.mkVerificationTools = import ./verification-tools.nix;

  perSystem =
    { pkgs, ... }:
    let
      slsa-pki = inputs.ghaf-infra-pki.packages.${pkgs.stdenv.hostPlatform.system}.slsa-pki;
      verificationTools = self.lib.mkVerificationTools {
        inherit pkgs;
        certificateDirectories.NetHSM = [
          "${slsa-pki}/share/ghaf-infra-pki/slsa/nethsm-tampere-mca"
          "${slsa-pki}/share/ghaf-infra-pki/slsa/nethsm-uae-mca"
        ];
      };
    in
    {
      legacyPackages = { inherit verificationTools; };
      packages = verificationTools;
    };
}
