# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    remote-build = {
      description = "User for remote builds";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM2rhqSdifRmTwyrc3rvXWyDMznrIAAkVwhEsufLYiTp"
      ];
      extraGroups = [ ];
    };
  };
  nix.settings.trusted-users = [ "remote-build" ];
}
