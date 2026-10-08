# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        select-pkcs11-node = pkgs.writeShellApplication {
          name = "select-pkcs11-node";
          runtimeInputs = with pkgs; [
            coreutils
            jq
            gnutls
          ];
          text = builtins.readFile ./scripts/select-pkcs11-node.sh;
        };

        run-cosign = pkgs.writeShellApplication {
          name = "run-cosign";
          runtimeInputs = with pkgs; [
            cosign
          ];
          text = builtins.readFile ./scripts/run-cosign.sh;
        };
      };
    };
}
