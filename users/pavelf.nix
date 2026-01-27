# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    pavelf = {
      description = "Pavel Fedorov";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH7MQKZ4CCzQ3aLm6Orh0NM+rTz8ykcmZdJg14yI0Rkc"
      ];
      extraGroups = [
        "networkmanager"
        "wheel"
        "dialout"
        "tty"
      ];
    };
  };
}
