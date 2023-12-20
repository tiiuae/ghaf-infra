# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    tervis = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDJau0tg0qHhqFVarjNOJLi+ekSZNNqxal4iRD/pwM5W tervis@tervis-thinkpad"
      ];
      extraGroups = ["wheel" "networkmanager" "docker"];
    };
  };
}
