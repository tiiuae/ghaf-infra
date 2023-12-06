# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  ...
}: {
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = lib.mkForce "no";
    settings.KbdInteractiveAuthentication = false;
    settings.PasswordAuthentication = false;
    settings.ClientAliveInterval = lib.mkDefault 60;
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };
  networking.firewall.allowedTCPPorts = [22];
  # Ban brute force SSH
  services.fail2ban.enable = true;

  environment.systemPackages = [
    pkgs.kitty.terminfo
  ];
}
