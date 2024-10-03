# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    maarit = {
      description = "Maarit Harkonen";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAJ0DcYPvtUwVh/D/fXphnhPpKX9j4JvgES1o0UeP+kY"
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
