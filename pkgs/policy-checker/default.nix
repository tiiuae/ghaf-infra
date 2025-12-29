# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  buildGoModule,
  lib,
  makeWrapper,
  selfPkgs,
  ...
}:
buildGoModule {
  pname = "policy-checker";
  version = "0.1";

  src = lib.cleanSource ./src;
  vendorHash = "sha256-0P/vmGoSYBSj4lLyw56vn8jEOP9innq53QXpLrXUKf0=";
  nativeBuildInputs = [ makeWrapper ];
  postInstall = ''
    wrapProgram $out/bin/policy-checker --prefix PATH : "${selfPkgs.verify-signature}/bin"
  '';
}
