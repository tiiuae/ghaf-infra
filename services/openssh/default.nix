# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, lib, ... }:
{
  services.openssh = {
    enable = true;

    settings = {
      PermitRootLogin = lib.mkForce "no";
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      ClientAliveInterval = lib.mkDefault 60;
    };

    # Only allow ed25519 keys
    extraConfig = ''
      PubkeyAcceptedKeyTypes ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,sk-ssh-ed25519@openssh.com,sk-ssh-ed25519-cert-v01@openssh.com
    '';

    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  # Open port for ssh connections
  networking.firewall.allowedTCPPorts = [ 22 ];

  # Ban brute force SSH
  services.fail2ban = {
    enable = true;
    bantime-increment.enable = true;
    jails.sshd.settings.filter = "sshd[mode=aggressive]";
    ignoreIP = [
      "109.204.204.138" # Tampere office IP address
    ];
  };

  environment.systemPackages = [ pkgs.kitty.terminfo ];
}
