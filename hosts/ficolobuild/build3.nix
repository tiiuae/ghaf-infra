# SPDX-FileCopyrightText: 2024 Technology Innovation Institute (TII)
# SPDX-License-Identifier: Apache-2.0
#
{
  self,
  lib,
  ...
}: {
  imports = lib.flatten [
    (with self.nixosModules; [
      user-themisto
      user-barna
      user-bmg
    ])
    ./builder.nix
  ];

  # build3 specific configuration

  networking.hostName = "build3";

  # Trust Themisto Hydra user
  nix.settings = {
    trusted-users = ["root" "themisto" "barna" "bmg"];
  };
}
