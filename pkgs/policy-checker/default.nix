# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
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
  vendorHash = "sha256-62fncETYANF2iqDDLosR+pv5XvGh3EACJ599bmH7BKw=";
}
