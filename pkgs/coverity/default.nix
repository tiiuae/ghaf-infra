# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  lib,
  autoPatchelfHook,
  fetchurl,
  curl,
  systemd,
  zlib,
  xorg,
  alsa-lib,
  libxcrypt-legacy,
  ...
}:
stdenv.mkDerivation {
  pname = "coverity";
  version = "2411.6";

  src = fetchurl {
    url = "https://archive.ssrcdevops.tii.ae/ghaf/cov-analysis.tar.gz";
    hash = "sha256-Jafs8hegK3fWcy9/YGhy4mnRVCdFj0BYKZoipkph7fc=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    # libudev
    (lib.getLib systemd)
    # libstdc++.so libgcc_s.so
    stdenv.cc.cc.lib
    # libcurl.so.4
    curl
    # libz.so.1
    zlib
    # libXext.so.6
    xorg.libXext
    # libX11.so.6
    xorg.libX11
    # libXrender.so.1
    xorg.libXrender
    # libXtst.so.6
    xorg.libXtst
    # libXi.so.6
    xorg.libXi
    # libasound2.so.2
    alsa-lib
    # libcrypt.so.1
    libxcrypt-legacy
  ];

  # Unpack the CLI tools.
  installPhase = ''
    mkdir -p $out/bin
    cp -r * $out 
  '';

  meta = with lib; {
    description = "Coverity Scan Tools";
    longDescription = ''
      Coverity tools for code analysis
    '';
    homepage = "https://coverity.com";
    platforms = [ "x86_64-linux" ];
    license = licenses.unfree;
    maintainers = with maintainers; [ TII ];
    mainProgram = "coverity";
  };
}
