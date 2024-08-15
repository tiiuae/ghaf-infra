# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    ktu = {
      description = "Kai Tusa";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBeMFr++WulL/hQKejDnE1ePRQscLp7LvLAy/DyLW4AU ktu@nixos"
      ];
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
    };
  };
}
