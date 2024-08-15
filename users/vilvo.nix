# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    vilvo = {
      description = "Ville Ilvonen";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFWXZk/ZFUaNAW+jeeTtDqu+9DS0BuBeLYwvZqpaLXQ8 vilvo@carrie"
      ];
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
    };
  };
}
