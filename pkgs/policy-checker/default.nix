# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  buildGoModule,
  lib,
  makeWrapper,
  verify-signature,
  ...
}:
buildGoModule {
  pname = "policy-checker";
  version = "0.1";

  src = lib.cleanSource ./src;
  vendorHash = "sha256-0P/vmGoSYBSj4lLyw56vn8jEOP9innq53QXpLrXUKf0=";
  nativeBuildInputs = [ makeWrapper ];
  preCheck = ''
    export RELEASE_POLICY_FILE=${../../slsa/release-policy.yaml}
  '';
  postInstall = ''
    wrapProgram $out/bin/policy-checker --prefix PATH : "${verify-signature}/bin"
  '';
}
