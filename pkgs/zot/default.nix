# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  zlib,
  openssl,
  stdenv,
}:

let
  version = "2.1.14";
  asset = if stdenv.hostPlatform.isAarch64 then "zot-linux-arm64" else "zot-linux-amd64";
in
stdenvNoCC.mkDerivation {
  pname = "zot";
  inherit version;

  src = fetchurl {
    url = "https://github.com/project-zot/zot/releases/download/v${version}/${asset}";
    sha256 = "sha256-yW4jlOHZTd00OfOxnR0rcH5by/NP7ElTKAW/PNc0v8c=";
  };

  dontUnpack = true;

  nativeBuildInputs = [ autoPatchelfHook ];

  buildInputs = [
    zlib
    openssl
  ];

  installPhase = ''
    mkdir -p $out/bin
    install -m755 $src $out/bin/zot
  '';
}
