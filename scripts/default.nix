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
        runtimeEnv = {
          YUBIHSM_CERT_DIR = "${
            inputs.ghaf-infra-pki.packages.${pkgs.stdenv.hostPlatform.system}.yubi-slsa-pki
          }/share/ghaf-infra-pki/slsa";
          NETHSM_CERT_DIR = "${
            inputs.ghaf-infra-pki.packages.${pkgs.stdenv.hostPlatform.system}.nethsm-slsa-pki-tampere
          }/share/ghaf-infra-pki/slsa-nethsm";
        };
        text = builtins.readFile ./verify-signature.sh;
      };
      archive-ghaf-release = pkgs.writeShellApplication {
        name = "archive-ghaf-release";
        runtimeInputs =
          (with pkgs; [
            minio-client
            oras
            tree
            jq
          ])
          ++ [
            ghaf-fetch
            verify-signature
          ];
        text = builtins.readFile ./archive-ghaf-release.sh;
      };
      ghaf-fetch = pkgs.writeShellApplication {
        name = "ghaf-fetch";
        runtimeInputs = with pkgs; [
          gum
          jq
          oras
        ];
        text = builtins.readFile ./ghaf-fetch.sh;
      };
    in
    {
      packages = {
        inherit
          verify-signature
          archive-ghaf-release
          ghaf-fetch
          ;
      };
    };
}
