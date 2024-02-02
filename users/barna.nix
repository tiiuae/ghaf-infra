# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    barna = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHrmxamlb4JNX+lrN88rfEEskCM0A5MhGSKaA4CZDM8y barna.bakos@unikie.com"
      ];
      extraGroups = ["wheel" "docker"];
    };
  };
}
