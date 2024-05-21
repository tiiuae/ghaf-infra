# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    mariia = {
      description = "Mariia Azbeleva";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMXq8i5FHMw7vRpAZeXnYux5e6xFgObJgq4+bnY/6s7f"
      ];
      extraGroups = ["networkmanager" "wheel" "dialout" "tty"];
    };
  };
}
