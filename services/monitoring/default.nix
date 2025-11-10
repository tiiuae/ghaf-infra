# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.services.monitoring;

  alloyConfigs = {
    base = # hcl
      ''
        loki.write "default" {
        	endpoint {
        		url = "${cfg.logs.lokiAddress}/loki/api/v1/push" 

        		basic_auth {
        			username      = "${cfg.logs.auth.username}"
        			${
             lib.optionalString (
               cfg.logs.auth.password_file != null
             ) ''password_file = "${cfg.logs.auth.password_file}"''
           }
        		}
        	}
        }
      '';

    journal =
      lib.mkIf cfg.logs.journal # hcl
        ''
          discovery.relabel "journal" {
          	targets = []

          	rule {
          		source_labels = ["__journal__systemd_unit"]
          		target_label  = "unit"
          	}
          }

          loki.source.journal "journal" {
          	relabel_rules = discovery.relabel.journal.rules
          	forward_to    = [loki.write.default.receiver]
          	labels        = {
          		host = "${config.networking.hostName}",
          		job  = "systemd-journal",
          	}
          }
        '';
  } // cfg.alloy.configFiles;
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
      journal = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable collecting systemd journal logs";
      };

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

    alloy = {
      configFiles = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.metrics.enable {
      services.prometheus.exporters = {
        node = {
          enable = true;
          enabledCollectors = [ "systemd" ];
          port = 9100;
        };
      };

      # with ProtectHome=true, the exporter will report incorrect filesystem bytes for /home
      systemd.services.prometheus-node-exporter.serviceConfig = {
        ProtectHome = lib.mkForce "read-only";
      };

      networking.firewall = lib.mkIf cfg.metrics.openFirewall {
        allowedTCPPorts = [ config.services.prometheus.exporters.node.port ];
        allowedUDPPorts = [ config.services.prometheus.exporters.node.port ];
      };

      # sshified user for monitoring server to log in as
      users.users.sshified = lib.mkIf cfg.metrics.ssh {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEKd30t0EFmMyULGlecaUX6puIAF4IjynZUo+X9k8h69 monitoring"
        ];
      };
    })
    (lib.mkIf cfg.logs.enable {
      services.alloy = {
        enable = true;
        configPath = "/etc/alloy";
        extraFlags = [
          "--server.http.listen-addr=127.0.0.1:9999"
          "--disable-reporting"
        ];
      };

      users.groups.alloy = { };
      users.users.alloy.isSystemUser = true;
      users.users.alloy.group = "alloy";

      systemd.services.alloy.serviceConfig.User = "alloy";
      systemd.services.alloy.serviceConfig.Group = "alloy";

      environment.etc = lib.mapAttrs' (
        name: content: lib.nameValuePair "alloy/${name}.alloy" { text = content; }
      ) alloyConfigs;
    })
  ];
}
