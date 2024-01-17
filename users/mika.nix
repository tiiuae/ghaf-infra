# SPDX-FileCopyrightText: 2024 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    mika = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKoroafXsrWkoLewJ7EYcHodqlYILV2T8xtRo6RL99vz mika@nixos"
      ];
      extraGroups = ["wheel" "networkmanager" "docker"];
    };
  };
}
