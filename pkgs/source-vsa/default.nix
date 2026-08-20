# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  cosign,
  lib,
  makeWrapper,
  oras,
  python3Packages,
}:
python3Packages.buildPythonApplication {
  pname = "source-vsa";
  version = "0.1.0";
  format = "other";

  src = ./src;

  propagatedBuildInputs = [ python3Packages.pyyaml ];
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm755 source_vsa.py $out/bin/source-vsa

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/source-vsa \
      --prefix PATH : ${
        lib.makeBinPath [
          cosign
          oras
        ]
      }
  '';

  meta = {
    description = "Issue and verify SLSA Source VSAs stored in OCI registries";
    license = lib.licenses.asl20;
    mainProgram = "source-vsa";
  };
}
