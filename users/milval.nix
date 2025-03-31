# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    milval = {
      description = "Milla Valio";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGll9sWYdGc2xi9oQ25TEcI1D3T4n8MMXoMT+lJdE/KC"
      ];
      extraGroups = [
        "networkmanager"
        "wheel"
        "dialout"
        "tty"
      ];
    };
  };
}
