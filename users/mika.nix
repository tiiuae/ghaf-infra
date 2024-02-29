# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    mika = {
      description = "Mika Nokka";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKoroafXsrWkoLewJ7EYcHodqlYILV2T8xtRo6RL99vz mika@nixos"
      ];
      extraGroups = ["wheel" "networkmanager" "docker"];
    };
  };
}
