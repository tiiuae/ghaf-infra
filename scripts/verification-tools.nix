# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  certificateDirectories,
}:
let
  verify-signature = pkgs.writeShellApplication {
    name = "verify-signature";
    runtimeInputs = with pkgs; [
      openssl
      jq
    ];
    runtimeEnv.SIGNATURE_CERTIFICATE_DIRECTORIES_FILE = toString (
      pkgs.writeText "signature-certificate-directories.json" (builtins.toJSON certificateDirectories)
    );
    text = builtins.readFile ./verify-signature.sh;
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
  inherit verify-signature ghaf-fetch;
  policy-checker = pkgs.callPackage ../pkgs/policy-checker { inherit verify-signature; };
  archive-ghaf-release = pkgs.writeShellApplication {
    name = "archive-ghaf-release";
    runtimeInputs =
      (with pkgs; [
        rclone
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
}
