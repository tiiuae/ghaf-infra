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
    ../azure-common-2.nix
    self.nixosModules.service-openssh
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

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
      # FUTUREWORK: set AZURE_STORAGE_ACCOUNT_NAME and storage container name through EnvironmentFile
      ExecStart =
        "${pkgs.rclone}/bin/rclone "
        + "serve http "
        + "--azureblob-env-auth "
        + "--azureblob-account ghafbinarycache "
        + "--read-only "
        + "--addr unix://%t/rclone-http/socket "
        + ":azureblob:binary-cache-v1";
      # On successful startup, grant caddy write permissions to the socket.
      ExecStartPost = "${pkgs.acl.bin}/bin/setfacl -m u:caddy:rw %t/rclone-http/socket";
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
      ghaf-binary-cache.northeurope.cloudapp.azure.com {
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

  # Expose the HTTP and HTTPS port.
  networking.firewall.allowedTCPPorts = [80 443];

  system.stateVersion = "23.05";
}
