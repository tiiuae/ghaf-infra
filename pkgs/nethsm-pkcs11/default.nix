# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  rustPlatform,
  fetchFromGitHub,
  ...
}:
rustPlatform.buildRustPackage rec {
  pname = "nethsm-pkcs11";
  version = "2.2.0";

  src = fetchFromGitHub {
    owner = "Nitrokey";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-SrranXfMUOckgRVGQTiD9os5H37eTc6G8Ayfbm5Fq38=";
  };

  dontUseCargoParallelTests = true;
  cargoHash = "sha256-2OcnOrTGk8pv32Iv1tQKq8CT9BhkDDLHxfdzQRJnTsQ=";
}
