# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  lib,
  ...
}:
let
  azure-nix-cache-proxy = pkgs.rustPlatform.buildRustPackage rec {
    name = "azure-nix-cache-proxy";
    version = "0.0.0";
    src = pkgs.fetchFromGitHub {
      owner = "tiiuae";
      repo = "azure-nix-cache-proxy";
      rev = "7e6b4e8b6e7081cd14aaadc63950f31eae2ae032";
      hash = "sha256-ZTr0AjYhZScjvUvvf/q6e4c5c4ndhnKHuf7y4UogSoM=";
    };
    cargoLock = {
      lockFile = "${src}/Cargo.lock";
      outputHashes = {
        "nix-compat-0.1.0" = "sha256-zdil1FMtKnnMWuN9yMqJcYTlwXR+QiPoq6wUi1OpJ+w=";
      };
    };
    meta = {
      description = "Expose a Azure Storage Container hosting Nix binary cache contents over HTTP.";
      homepage = "https://github.com/tiiuae/azure-nix-cache-proxy";
      license = lib.licenses.gpl3Plus;
    };
  };
in
{
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

  systemd.services.azure-nix-cache-proxy = {
    serviceConfig = {
      ExecStart = "${azure-nix-cache-proxy}/bin/azure-nix-cache-proxy -l sd-listen binary-cache-v1";
      EnvironmentFile = "/var/lib/azure-nix-cache-proxy/env";
    };
  };

  systemd.sockets.azure-nix-cache-proxy = {
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "/run/azure-nix-cache-proxy.sock";
      # Grant (only) caddy write permissions to the socket.
      SocketMode = "0600";
      SocketUser = "caddy";
    };
  };

  # Expose the azure-nix-cache-proxy unix socket over a HTTPS, limiting to certain
  # keys only, disallowing listing too.
  services.caddy = {
    enable = true;
    configFile = pkgs.writeText "Caddyfile" ''
      # Disable the admin API, we don't want to reconfigure Caddy at runtime.
      {
        admin off
      }

      # Proxy a subset of requests to azure-nix-cache-proxy.
      {$SITE_ADDRESS} {
        handle /nix-cache-info {
          reverse_proxy unix///run/azure-nix-cache-proxy.sock
        }
        handle /*.narinfo {
          reverse_proxy unix///run/azure-nix-cache-proxy.sock
        }
        handle /nar/*.nar {
          reverse_proxy unix///run/azure-nix-cache-proxy.sock
        }
        handle /nar/*.nar.* {
          reverse_proxy unix///run/azure-nix-cache-proxy.sock
        }
      }
    '';
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile = "/var/lib/caddy/caddy.env";

  # Configure Nix to use the bucket (through rclone-http) as a substitutor.
  # The public key is passed in externally.
  nix.settings.substituters = [ "http://localhost:8080" ];

  # Wait for cloud-init mounting before we start caddy.
  systemd.services.caddy.after = [ "cloud-init.service" ];
  systemd.services.caddy.requires = [ "cloud-init.service" ];

  # Expose the HTTP[S] port. We still need HTTP for the HTTP-01 challenge.
  # While TLS-ALPN-01 could be used, disabling HTTP-01 seems only possible from
  # the JSON config, which won't work alongside Caddyfile.
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  system.stateVersion = "23.05";
}
