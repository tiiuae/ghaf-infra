# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  self,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../../azure-common.nix
    self.nixosModules.service-openssh
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

  # Run a read-only HTTP webserver proxying to the "binary-cache-v1" storage
  # container at a unix socket.
  # This relies on IAM to grant access to the storage container.
  systemd.services.rclone-http = {
    after = ["network.target"];
    requires = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "notify";
      Restart = "always";
      RestartSec = 2;
      DynamicUser = true;
      RuntimeDirectory = "rclone-http";
      ExecStart =
        "${pkgs.rclone}/bin/rclone "
        + "serve http "
        + "--azureblob-env-auth "
        + "--read-only "
        + "--addr unix://%t/rclone-http/socket "
        + ":azureblob:binary-cache-v1";
      # On successful startup, grant caddy write permissions to the socket.
      ExecStartPost = "${pkgs.acl.bin}/bin/setfacl -m u:caddy:rw %t/rclone-http/socket";
      EnvironmentFile = "/var/lib/rclone-http/env";
    };
  };

  # Expose the rclone-http unix socket over a HTTPS, limiting to certain
  # keys only, disallowing listing too.
  # TODO: use https://caddyserver.com/docs/caddyfile-tutorial#environment-variables for domain
  services.caddy = {
    enable = true;
    configFile = pkgs.writeTextDir "Caddyfile" ''
      # Disable the admin API, we don't want to reconfigure Caddy at runtime.
      {
        admin off
      }

      # Proxy a subset of requests to rclone.
      https://{$SITE_ADDRESS} {
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

  # workaround for https://github.com/NixOS/nixpkgs/issues/272532
  # FUTUREWORK: rebase once https://github.com/NixOS/nixpkgs/pull/272617 landed
  services.caddy.enableReload = false;
  systemd.services.caddy.serviceConfig.ExecStart = lib.mkForce [
    ""
    "${pkgs.caddy}/bin/caddy run --environ --config ${config.services.caddy.configFile}/Caddyfile"
  ];
  systemd.services.caddy.serviceConfig.EnvironmentFile = "/run/caddy.env";

  # Wait for cloud-init mounting before we start caddy.
  systemd.services.caddy.after = ["cloud-init.service"];
  systemd.services.caddy.requires = ["cloud-init.service"];

  # Expose the HTTPS port. No need for HTTP, as caddy can use TLS-ALPN-01.
  networking.firewall.allowedTCPPorts = [443];

  system.stateVersion = "23.05";
}
