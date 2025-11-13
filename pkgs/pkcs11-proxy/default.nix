# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  stdenv,
  fetchFromGitHub,
  ...
}:
let
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.pykcs11 ]);
in
stdenv.mkDerivation {
  pname = "pkcs11-proxy";
  version = "git";

  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = "bukka-pkcs11-proxy";
    rev = "ed05bbe92a02e27a615c3f4b1b5e7f4f529f5dec";
    hash = "sha256-3lYX2JpclYDx35kqNIFC8IWW9HEe1C6QoD+CGK5NcBc=";
  };

  buildInputs = [
    pkgs.makeWrapper
    pythonEnv
  ];

  nativeBuildInputs = with pkgs; [
    cmake
    pkg-config
    openssl
    libseccomp
  ];

  postInstall = ''
    cp ../tools/p11proxy-mitm $out/bin/
    patchShebangs $out/bin/p11proxy-mitm
    wrapProgram $out/bin/p11proxy-mitm \
      --set PATH "${pythonEnv}/bin" \
      --prefix PYTHONPATH : "${pythonEnv}/${pkgs.python3.sitePackages}"
  '';

  postPatch = ''
    patchShebangs mksyscalls.sh
  '';

  meta.mainProgram = "pkcs11-daemon";
}
