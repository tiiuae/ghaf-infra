# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{pkgs, ...}: {
  # Yubikey provisioning
  users.users.yubimaster = {
    description = "Yubikey Signer";
    isNormalUser = true;
    extraGroups = ["docker"];
  };

  environment.systemPackages = with pkgs; [
    usbutils
    screen
    (python310.withPackages (ps:
      with ps; [
        requests
      ]))
  ];

  virtualisation.docker.enable = true;
}
