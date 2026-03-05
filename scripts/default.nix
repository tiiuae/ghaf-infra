# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      verify-signature = pkgs.writeShellApplication {
        name = "verify-signature";
        runtimeInputs = with pkgs; [
          openssl
        ];
        runtimeEnv =
          let
            keySource = inputs.ghaf-infra-pki.packages.${pkgs.stdenv.hostPlatform.system}.yubi-slsa-pki;
          in
          {
            IMG_CERT = "${keySource}/share/ghaf-infra-pki/slsa/GhafInfraSignECP256.pem";
            PROV_CERT = "${keySource}/share/ghaf-infra-pki/slsa/GhafInfraSignProv.pem";
          };
        text = builtins.readFile ./verify-signature.sh;
      };
      archive-ghaf-release = pkgs.writeShellApplication {
        name = "archive-ghaf-release";
        runtimeInputs =
          (with pkgs; [
            minio-client
            tree
            jq
          ])
          ++ [
            verify-signature
          ];
        text = builtins.readFile ./archive-ghaf-release.sh;
      };
    in
    {
      packages = {
        inherit verify-signature archive-ghaf-release;
      };
    };
}
