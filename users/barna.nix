# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    barna = {
      description = "Barna Bakos";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHrmxamlb4JNX+lrN88rfEEskCM0A5MhGSKaA4CZDM8y barna.bakos@unikie.com"
      ];
      extraGroups = [
        "wheel"
        "docker"
      ];
    };
  };
}
