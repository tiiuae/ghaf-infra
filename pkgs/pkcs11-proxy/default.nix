# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  stdenv,
  fetchFromGitHub,
  ...
}:
stdenv.mkDerivation rec {
  pname = "pkcs11-proxy";
  version = "git";

  src = fetchFromGitHub {
    owner = "scobiej";
    repo = pname;
    rev = "f9329e16cca1de3b0337a21e9cdab5be9e27a471";
    hash = "sha256-zFPjAvm7O3gPvlCSPXn/QnCIzaWAdtKa6ISFsEfhjLs=";
  };

  nativeBuildInputs = with pkgs; [
    cmake
    pkg-config
    openssl
    libseccomp
  ];

  postPatch = ''
    patchShebangs mksyscalls.sh
  '';
}
