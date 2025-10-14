# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  systemd,
  ...
}:
# systemd-sbsign is in the package but not exposed in PATH
# https://github.com/NixOS/nixpkgs/issues/447999
# Create a wrapper derivation that just adds it to $out/bin
stdenv.mkDerivation {
  name = "systemd-sbsign";
  # noop unpackPhase as there is no $src aside of systemd
  unpackPhase = "true";
  buildInputs = [ systemd ];
  installPhase = ''
    mkdir -p $out/bin
    ln -s ${systemd}/lib/systemd/systemd-sbsign $out/bin/systemd-sbsign
  '';
}
