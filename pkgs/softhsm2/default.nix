# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  openssl,
  sqlite,
  ...
}:
stdenv.mkDerivation rec {
  pname = "softhsm2";
  version = "2.7.0";

  src = fetchFromGitHub {
    owner = "softhsm";
    repo = "SoftHSMv2";
    tag = version;
    sha256 = "sha256-gwqdgGCVPQwPkE6gFlZxZdk6Ln/qZn3CmMfbcLm9p04=";
  };

  nativeBuildInputs = [
    autoreconfHook
    openssl
    sqlite
  ];

  # use openssl backend instead of botan
  # https://github.com/openssl/openssl/issues/22508#issuecomment-2646121200
  configureFlags = [
    "--with-crypto-backend=openssl"
    "--with-openssl=${lib.getDev openssl}"
    "--with-objectstore-backend-db"
    "--sysconfdir=$out/etc"
    "--localstatedir=$out/var"
  ];

  postInstall = ''
    rm -rf $out/var
  '';
}
