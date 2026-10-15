# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.monitoring;

  driftMetrics = pkgs.writeShellApplication {
    name = "ghaf-deployment-metrics";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      output_dir="''${1:-/run/ghaf-deployment-metrics}"
      mkdir -p "$output_dir"
      tmp="$(mktemp "$output_dir/.deployment.prom.XXXXXX")"
      trap 'rm -f "$tmp"' EXIT

      # Pin both profiles so revisions and timestamps refer to the same systems.
      running_system="$(readlink -e /run/current-system 2>/dev/null || true)"
      next_system="$(readlink -e /nix/var/nix/profiles/system 2>/dev/null || true)"

      revision_label() {
        local revision
        revision="$("$1/sw/bin/nixos-version" --configuration-revision 2>/dev/null || true)"
        printf '%s' "''${revision:-(unknown)}"
      }

      running_revision="$(revision_label "$running_system")"
      next_boot_revision="$(revision_label "$next_system")"

      # Dirty trees have a modification time, not a reliable commit time.
      revision_timestamp="$(cat "$running_system/etc/configuration-revision-timestamp" 2>/dev/null || true)"
      if [[ ! "$running_revision" =~ ^[0-9a-f]{40}$ || ! "$revision_timestamp" =~ ^[1-9][0-9]*$ ]]; then
        revision_timestamp=NaN
      fi

      # Same kernel versions as tasks.py: uname, and the next-boot kernel modules directory.
      running_kernel="$(uname -r)"
      next_boot_kernel="(unknown)"
      next_modules=("$next_system"/kernel-modules/lib/modules/*)
      if [ -n "$next_system" ] && [ "''${#next_modules[@]}" -eq 1 ] && [ -d "''${next_modules[0]}" ]; then
        next_boot_kernel="''${next_modules[0]##*/}"
      fi

      reboot_pending=NaN
      # Same kernel/initrd/modules comparison as tasks.py; missing artifacts are unknown.
      if [ -n "$next_system" ] && booted="$(readlink -e \
        /run/booted-system/initrd \
        /run/booted-system/kernel \
        /run/booted-system/kernel-modules 2>/dev/null)" &&
        next_boot="$(readlink -e \
          "$next_system/initrd" \
          "$next_system/kernel" \
          "$next_system/kernel-modules" 2>/dev/null)"; then
        reboot_pending=0
        if [ "$booted" != "$next_boot" ]; then
          reboot_pending=1
        fi
      fi

      cat > "$tmp" <<EOF
      # HELP ghaf_deployment_info Running and next-boot configuration revisions and kernels.
      # TYPE ghaf_deployment_info gauge
      ghaf_deployment_info{running_revision="$running_revision",next_boot_revision="$next_boot_revision",running_kernel="$running_kernel",next_boot_kernel="$next_boot_kernel"} 1
      # HELP ghaf_deployment_revision_timestamp_seconds Running revision commit time in Unix seconds (NaN if unknown or dirty).
      # TYPE ghaf_deployment_revision_timestamp_seconds gauge
      ghaf_deployment_revision_timestamp_seconds $revision_timestamp
      # HELP ghaf_deployment_reboot_pending Booted kernel, initrd or modules differ from next boot (NaN if unknown).
      # TYPE ghaf_deployment_reboot_pending gauge
      ghaf_deployment_reboot_pending $reboot_pending
      EOF
      chmod 0644 "$tmp"
      mv -fT "$tmp" "$output_dir/deployment.prom"
    '';
  };

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
  }
  // cfg.alloy.configFiles;
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
          enabledCollectors = [
            "systemd"
            "textfile"
          ];
          extraFlags = [ "--collector.textfile.directory=/run/ghaf-deployment-metrics" ];
          port = 9100;
        };
      };

      # with ProtectHome=true, the exporter will report incorrect filesystem bytes for /home
      systemd.services.prometheus-node-exporter.serviceConfig = {
        ProtectHome = lib.mkForce "read-only";
      };

      systemd.services.ghaf-deployment-metrics = {
        description = "Export deployment drift metrics";
        wantedBy = [ "multi-user.target" ];
        before = [ "prometheus-node-exporter.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe driftMetrics;
          RuntimeDirectory = "ghaf-deployment-metrics";
          RuntimeDirectoryPreserve = "yes";
          RuntimeDirectoryMode = "0755";
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
        };
      };

      systemd.timers.ghaf-deployment-metrics = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitActiveSec = "5min";
        };
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
        # See the nixpkgs-alloy input in flake.nix.
        package = inputs.nixpkgs-alloy.legacyPackages.${pkgs.stdenv.hostPlatform.system}.grafana-alloy;
        configPath = "/etc/alloy";
        extraFlags = [
          "--server.http.listen-addr=127.0.0.1:9999"
          "--disable-reporting"
        ];
      };

      systemd.services.alloy.serviceConfig = {
        User = "alloy";
        Group = "alloy";
        # alloy refuses to stop blocking shutdown
        TimeoutStopSec = "5s";
      };

      users.groups.alloy = { };
      users.users.alloy = {
        isSystemUser = true;
        group = "alloy";
      };

      environment.etc = lib.mapAttrs' (
        name: content: lib.nameValuePair "alloy/${name}.alloy" { text = content; }
      ) alloyConfigs;
    })
  ];
}
