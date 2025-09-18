# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ buildGoModule, fetchFromGitHub }:
buildGoModule rec {
  pname = "sshified";
  version = "v1.1.19";

  src = fetchFromGitHub {
    owner = "hoffie";
    repo = pname;
    rev = version;
    hash = "sha256-LgR2U0xcY/852ddSsPhaVJEWaKA2O8t0mpjM/PM9gn0=";
  };

  vendorHash = null;

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${version}"
  ];

  subPackages = [ "." ];

  meta.mainProgram = pname;
}
