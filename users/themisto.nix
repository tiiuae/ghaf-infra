# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    themisto = {
      description = "Themisto Hydra";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMK29aVdB0Xucg9pFMqkY6fwUKV41enaWw4wP7fUjOvK cazfi@gerrit"
      ];
    };
  };

  nix.settings.trusted-users = ["themisto"];
}
