# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    ctsopokis = {
      description = "Christos Tsopokis";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK0AWQPp/xHcTQbdktxzbR+/wR0zg9QzM4D5A3Trds4r"
      ];
      extraGroups = [
        "wheel"
        "networkmanager"
        "nethsm"
      ];
    };
  };
}
