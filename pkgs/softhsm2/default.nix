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
stdenv.mkDerivation {
  pname = "softhsm2";

  # nixpkgs provides 2.6.1, which is from 2020.
  # softhsm2 has not had a new release or tag in over 5 years.
  # Using the latest from git is better than using an outdated release.
  version = "develop";

  src = fetchFromGitHub {
    owner = "softhsm";
    repo = "SoftHSMv2";
    # head of develop branch
    rev = "25b94d4752739fc5954e7eb3a404810db5d632fa";
    sha256 = "sha256-yjcS8Jm7XAEqa1DrE0FcbccvubcRl+UlUeNp56NUVi8=";
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
