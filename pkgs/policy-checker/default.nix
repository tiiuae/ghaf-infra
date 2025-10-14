# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  buildGoModule,
  lib,
  ...
}:
buildGoModule {
  pname = "policy-checker";
  version = "0.1";

  src = lib.cleanSource ./.;
  vendorHash = "sha256-solbdcc0SeZYo3hqDVWjZjibJ4gjKP2U+FbZWaJmedY=";
}
