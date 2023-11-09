# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    nix = {
      isNormalUser = true;
      group = "nix";
      home = "/var/lib/nix";
      createHome = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIQwSH1R9xShZg1w5dZjRagYLae0QFBPYT3i80iHW1Ej"
      ];
    };
  };
  users.groups.nix = {};
  nix.settings.trusted-users = ["nix"];
}
