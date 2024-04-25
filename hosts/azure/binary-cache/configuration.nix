# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../../azure-common.nix
    self.nixosModules.service-openssh
    self.nixosModules.service-rclone-http
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Configure /var/lib/caddy in /etc/fstab.
  # Due to an implicit RequiresMountsFor=$state-dir, systemd
  # will block starting the service until this mounted.
  fileSystems."/var/lib/caddy" = {
    device = "/dev/disk/by-lun/10";
    fsType = "ext4";
    options = [
      "x-systemd.makefs"
      "x-systemd.growfs"
    ];
  };

  services.rclone-http = {
    enable = true;
    listenAddress = "%t/rclone-http/socket";
    readOnly = true;
    remote = ":azureblob:binary-cache-v1";
  };

  # Grant (only) caddy write permissions to the socket.
  systemd.sockets.rclone-http.socketConfig.SocketMode = "0600";
  systemd.sockets.rclone-http.socketConfig.SocketUser = "caddy";

  # Expose the rclone-http unix socket over a HTTPS, limiting to certain
  # keys only, disallowing listing too.
  services.caddy = {
    enable = true;
    configFile = pkgs.writeText "Caddyfile" ''
      # Disable the admin API, we don't want to reconfigure Caddy at runtime.
      {
        admin off
      }

      # Proxy a subset of requests to rclone.
      {$SITE_ADDRESS} {
        handle /nix-cache-info {
          reverse_proxy unix///run/rclone-http/socket
        }
        handle /*.narinfo {
          reverse_proxy unix///run/rclone-http/socket
        }
        handle /nar/*.nar {
          reverse_proxy unix///run/rclone-http/socket
        }
        handle /nar/*.nar.* {
          reverse_proxy unix///run/rclone-http/socket
        }
      }
    '';
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile = "/var/lib/caddy/caddy.env";

  # Configure Nix to use the bucket (through rclone-http) as a substitutor.
  # The public key is passed in externally.
  nix.settings.substituters = [
    "http://localhost:8080"
  ];

  # Wait for cloud-init mounting before we start caddy.
  systemd.services.caddy.after = ["cloud-init.service"];
  systemd.services.caddy.requires = ["cloud-init.service"];

  # Expose the HTTPS port. No need for HTTP, as caddy can use TLS-ALPN-01.
  networking.firewall.allowedTCPPorts = [443];

  system.stateVersion = "23.05";
}
