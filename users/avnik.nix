# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    avnik = {
      description = "Alexander Nikolaev";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFi/TNnF6Qvh9UhrHYocJE2CaL4TVZSg6Z+mX8F8LS/v avn@bulldozer"
      ];
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
    };
  };
}
