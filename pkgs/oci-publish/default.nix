# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  makeWrapper,
  oras,
  python3Packages,
  ...
}:
python3Packages.buildPythonApplication rec {
  pname = "oci-publish";
  version = "0.1.0";
  format = "other";

  src = ./src;

  nativeBuildInputs = [
    makeWrapper
  ];

  installPhase = ''
    install -Dm755 oci_publish.py "$out/bin/${pname}"
    patchShebangs "$out/bin/${pname}"
  '';

  postFixup = ''
    wrapProgram "$out/bin/${pname}" \
      --prefix PATH : "${lib.makeBinPath [ oras ]}"
  '';

  meta.mainProgram = pname;
}
