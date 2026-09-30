# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    xzr = {
      description = "Atte Pellikka";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG1fQw2Q2wXY9Ph9UxriraLMfHundeBT0ZRtFYY0xfmV atte.pellikka@tii.ae"
      ];
      extraGroups = [
        "wheel"
        "nethsm"
      ];
    };
  };
}
