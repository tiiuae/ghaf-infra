# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    mariia = {
      description = "Mariia Azbeleva";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM3TWpdHLfTiL9mvw4REkUrd/ob5Nto8XqSIrPPhn7gG mariiaazbeleva@nixos"
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
