# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    uae-remote-build = {
      description = "User for remote builds in UAE azureci";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG23fArR5mkx9eCHVKZ2EN/fqxR5LcXKkz4e8DSwLwG+"
      ];
      extraGroups = [ ];
    };
  };
  nix.settings.trusted-users = [ "uae-remote-build" ];
}
