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
    ])
    ./builder.nix
  ];

  # build4 specific configuration

  networking.hostName = "build4";

  # Yubikey signer
  users.users = {
    yubimaster = {
      isNormalUser = true;
      extraGroups = ["docker"];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA2BcpFzSXOuK9AzN+J1HBVnuVV8D3wgdEwPuILNy2aM signer"
      ];
    };
  };

  # Trust Themisto Hydra user
  nix.settings = {
    trusted-users = ["root" "themisto"];
  };
}
