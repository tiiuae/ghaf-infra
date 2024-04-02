# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    vjuntunen = {
      description = "Ville-Pekka Juntunen";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBJvhDUiX05DpsnQ1T8Fmoj2qVrInF8NeDSm8WiDeIxR"
      ];
      extraGroups = ["networkmanager" "wheel"];
    };
  };
}
