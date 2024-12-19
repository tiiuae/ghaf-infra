# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.services.monitoring;
in
{
  options.services.monitoring = {
    metrics = {
      enable = lib.mkEnableOption "Expose metrics";
      openFirewall = lib.mkEnableOption "Open firewall ports";
      ssh = lib.mkEnableOption "Allow ssh access from monitoring server";
    };

    logs = {
      enable = lib.mkEnableOption "Push logs";

      lokiAddress = lib.mkOption {
        type = lib.types.str;
        description = "The address to send logs to";
      };

      auth = {
        username = lib.mkOption {
          type = lib.types.str;
          default = "logger";
        };

        password_file = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
        };
      };
    };

  };

  config = {
    networking.firewall = lib.mkIf cfg.metrics.openFirewall {
      allowedTCPPorts = [ config.services.prometheus.exporters.node.port ];
      allowedUDPPorts = [ config.services.prometheus.exporters.node.port ];
    };

    services.prometheus.exporters = lib.mkIf cfg.metrics.enable {
      node = {
        enable = true;
        enabledCollectors = [ "systemd" ];
        port = 9100;
      };
    };

    # with ProtectHome=true, the exporter will report incorrect filesystem bytes for /home
    systemd.services.prometheus-node-exporter.serviceConfig = lib.mkIf cfg.metrics.enable {
      ProtectHome = lib.mkForce "read-only";
    };

    # sshified user for monitoring server to log in as
    users.users.sshified = lib.mkIf cfg.metrics.ssh {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEKd30t0EFmMyULGlecaUX6puIAF4IjynZUo+X9k8h69 monitoring"
      ];
    };

    services.promtail = lib.mkIf cfg.logs.enable {
      enable = true;
      configuration = {
        # We have no need for the HTTP or GRPC server
        server.disable = true;

        clients = [
          {
            url = "${cfg.logs.lokiAddress}/loki/api/v1/push";

            basic_auth = lib.mkIf (cfg.logs.auth.password_file != null) {
              inherit (cfg.logs.auth) username password_file;
            };
          }
        ];

        scrape_configs = [
          {
            job_name = "journal";
            journal = {
              max_age = "12h";
              labels = {
                job = "systemd-journal";
                host = config.networking.hostName;
              };
            };

            relabel_configs = [
              {
                source_labels = [ "__journal__systemd_unit" ];
                target_label = "unit";
              }
            ];
          }
        ];
      };
    };
  };
}
