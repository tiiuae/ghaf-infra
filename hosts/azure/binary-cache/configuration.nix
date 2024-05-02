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
    listenAddress = "%t/rclone-http.sock";
    extraArgs = [
      "--azureblob-env-auth"
    ];
    remote = ":azureblob:binary-cache-v1";
  };

  # Grant (only) caddy write permissions to the socket.
  # Note how we explicitly do NOT put the socket file in the rclone-http runtime
  # directory.
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
          reverse_proxy unix///run/rclone-http.sock
        }
        handle /*.narinfo {
          reverse_proxy unix///run/rclone-http.sock
        }
        handle /nar/*.nar {
          reverse_proxy unix///run/rclone-http.sock
        }
        handle /nar/*.nar.* {
          reverse_proxy unix///run/rclone-http.sock
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

  # Expose the HTTP[S] port. We still need HTTP for the HTTP-01 challenge.
  # While TLS-ALPN-01 could be used, disabling HTTP-01 seems only possible from
  # the JSON config, which won't work alongside Caddyfile.
  networking.firewall.allowedTCPPorts = [80 443];

  system.stateVersion = "23.05";
}
