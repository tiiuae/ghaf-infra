# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    tester = {
      description = "Tester User";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIFbxhIZjGU6JuMBMMyeaYNXSltPCjYzGZ2WSOpegPuQ"
      ];
      extraGroups = ["wheel" "networkmanager"];
    };
  };
}
