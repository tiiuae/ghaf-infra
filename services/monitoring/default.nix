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
    };

    logs = {
      enable = lib.mkEnableOption "Push logs";

      lokiAddress = lib.mkOption {
        type = lib.types.str;
        default = "http://172.18.20.108";
        description = "The address to send logs to";
      };
    };

  };

  config = {

    networking.firewall = lib.mkIf cfg.metrics.enable {
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

    services.promtail = lib.mkIf cfg.logs.enable {
      enable = true;
      configuration = {
        # We have no need for the HTTP or GRPC server
        server.disable = true;

        clients = [ { url = "${cfg.logs.lokiAddress}/loki/api/v1/push"; } ];

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
