# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  ...
}: {
  imports = lib.flatten [
    (with self.nixosModules; [
      user-themisto
      user-ktu
      user-avnik
    ])
    ./builder.nix
    ./developers.nix
  ];

  # build3 specific configuration

  networking.hostName = "build3";

  # Yubikey signer
  users.users = {
    yubimaster = {
      description = "Yubikey Signer";
      isNormalUser = true;
      extraGroups = ["docker"];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMDfEUoARtE5ZMYofegtm3lECzaQeAktLQ2SqlHcV9jL signer"
      ];
    };
  };

  # Trust Themisto Hydra user
  nix.settings = {
    trusted-users = ["root" "themisto" "@wheel"];
  };
}
