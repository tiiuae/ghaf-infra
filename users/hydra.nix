# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    hydra = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILbycq53k6oz1VvTC8I7wYt1c5t2YGYd41MJUeakte5t hydra@build4"
      ];
      extraGroups = [];
    };
  };
}
