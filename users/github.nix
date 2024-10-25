# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    github = {
      description = "Github actions runners can use this user to remote build";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH/KOBOKqZwugt7Yi6ZFhr6ZF2j9kzyqnl+v7eRlxPoq"
      ];
      extraGroups = [ ];
    };
  };
  nix.settings.trusted-users = [ "github" ];
}
