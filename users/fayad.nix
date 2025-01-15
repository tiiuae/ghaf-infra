# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    fayad = {
      description = "Fayad Fami";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKn694TOPl6NvWsFYj2dfO4Lv083Tv7mQRPv9Ik+jxcY fayad@3seven"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAzseP8ZDS7merc6GAExuNJW6eg01ZWh/V3sVuFIREEK fayad@n1xb0x"
      ];
      extraGroups = [ "wheel" ];
    };
  };
}
