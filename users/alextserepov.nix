# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    alextserepov = {
      description = "Aleksandr Tserepov-Savolainen";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJvQdncdNCFMw7f0Xln40H/u0fJp82tVrQMEHtSdvP6m aleksandr.tserepov-savolainen@unikie.com"
      ];
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
    };
  };
}
