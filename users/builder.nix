# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
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
