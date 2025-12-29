# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        verify-signature = pkgs.writeShellApplication {
          name = "verify-signature";
          runtimeInputs = with pkgs; [
            openssl
          ];
          runtimeEnv = {
            IMG_CERT = "${../keys/GhafInfraSignECP256.pem}";
            PROV_CERT = "${../keys/GhafInfraSignProv.pem}";
          };
          text = builtins.readFile ./verify-signature.sh;
        };
      };
    };
}
