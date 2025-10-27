# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  rustPlatform,
  fetchFromGitHub,
  ...
}:
rustPlatform.buildRustPackage rec {
  pname = "nethsm-pkcs11";
  version = "2.0.0";

  src = fetchFromGitHub {
    owner = "Nitrokey";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-qTuRBwXrl+tqswmwVHBblVL9JJGMImh4L+jyByViKaQ=";
  };

  cargoHash = "sha256-j1M9TUXdK1+8Zl9XV4uxQDbR9RUwoAnB0OctrUksvKs=";

  # meta.mainProgram = "pkcs11-daemon";
}
