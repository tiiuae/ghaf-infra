# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
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
