# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    mikkos = {
      description = "Mikko Saarinen";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILDvhfh9J9ac5+9QQ9FdSQe9XK5fiJf8z8kcWzQfjsWv"
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
