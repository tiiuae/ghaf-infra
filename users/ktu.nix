# SPDX-FileCopyrightText: 2024 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    ktu = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBeMFr++WulL/hQKejDnE1ePRQscLp7LvLAy/DyLW4AU ktu@nixos"
      ];
      extraGroups = ["wheel" "networkmanager"];
    };
  };
}
