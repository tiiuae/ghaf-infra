# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "sshified";
  version = "1.1.15";

  src = fetchFromGitHub {
    owner = "hoffie";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-zbgwCWs+DNJ1ZmAl9h0PuJvLO3yMhE/t6T1aqpwYOgk=";
  };

  vendorHash = null;

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${version}"
  ];

  subPackages = ["."];
}
