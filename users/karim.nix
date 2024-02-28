# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
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
