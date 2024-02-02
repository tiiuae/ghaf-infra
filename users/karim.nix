# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    karim = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOWo1W2XgAYxqntPxdI0k7K/3EgWB6lAaPkEwUwUT2Ey karim@nixos"
      ];
      extraGroups = ["wheel" "networkmanager"];
    };
  };
}
