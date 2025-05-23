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
  vendorHash = "sha256-h8Nek79pg1DFFnWdzQA2g1VucvxQLurPf8aK7uhqt7Q=";
}
