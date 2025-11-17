# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  stdenv,
  fetchFromGitHub,
  withDebug ? false,
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
    repo = "pkcs11-proxy";
    rev = "199f00f0874b8c0bdc34a90203171a11a791be7f";
    hash = "sha256-xX3fdX3g+U+gdOark3vNv+/QDDHyXSc6kwhq7VWNUpo=";
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

  cmakeFlags = if withDebug then [ "-DENABLE_DEBUG_OUTPUT=1" ] else [ ];

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
