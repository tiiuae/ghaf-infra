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
stdenv.mkDerivation rec {
  pname = "pkcs11-proxy";
  version = "git";

  src = fetchFromGitHub {
    owner = "joinemm";
    repo = pname;
    rev = "26f7d4665b727d63f2bfdc9560eadff0a2866701";
    hash = "sha256-qFvLmfiYCK6yw+dNPcZtK1RySfJLr0Jhfkn0lEx74MU=";
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
    cp ../p11proxy-mitm $out/bin/
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
