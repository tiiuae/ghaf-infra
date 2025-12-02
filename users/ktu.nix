# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    ktu = {
      description = "Kai Tusa";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMW15uyZmW0ICy2YxwiWAWqLP4NmOI8YsswXgdavwqVS x1"
      ];
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
    };
  };
}
