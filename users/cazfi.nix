# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    cazfi = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHzAww8Md+anrVfg93jNYey35Lu/YPEdbEh9QRu+riyf cazfi@cazfi-wlt"
      ];
      extraGroups = ["wheel" "networkmanager" "docker"];
    };
  };
}
