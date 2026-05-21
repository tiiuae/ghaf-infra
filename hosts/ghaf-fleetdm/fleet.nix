# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  self,
  ...
}:

let
  domain = "fleetdm.vedenemo.dev";
  fleetPort = 1337;
  inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) fleet fleetctl;
in
{
  environment.systemPackages = [
    fleet
    fleetctl
  ];

  users.groups.fleet = { };

  users.users.fleet = {
    isSystemUser = true;
    group = "fleet";
    home = "/var/lib/fleet";
    createHome = true;
  };

  sops.secrets."fleet-private-key" = {
    owner = "fleet";
    group = "fleet";
    mode = "0400";
  };

  sops.templates."fleet-env" = {
    owner = "fleet";
    group = "fleet";
    mode = "0400";
    restartUnits = [ "fleetdm.service" ];

    content = ''
      FLEET_SERVER_PRIVATE_KEY=${config.sops.placeholder."fleet-private-key"}
    '';
  };

  services.mysql = {
    enable = true;
    package = pkgs.mysql84;

    ensureDatabases = [
      "fleet"
    ];

    ensureUsers = [
      {
        name = "fleet";
        ensurePermissions = {
          "fleet.*" = "ALL PRIVILEGES";
        };
      }
    ];
  };

  services.redis.servers.fleet = {
    enable = true;
    bind = "127.0.0.1";
    port = 6379;
  };

  # Fleet configuration
  environment.etc."fleet/fleet.yml".text = ''
    mysql:
      protocol: unix
      address: /run/mysqld/mysqld.sock
      database: fleet
      username: fleet

    redis:
      address: 127.0.0.1:${toString config.services.redis.servers.fleet.port}
      database: 0

    server:
      address: 127.0.0.1:${toString fleetPort}
      tls: false
      trusted_proxies: "header:X-Real-IP"

    osquery:
      status_log_plugin: filesystem
      result_log_plugin: filesystem

    filesystem:
      status_log_file: /var/log/fleet/osqueryd.status.log
      result_log_file: /var/log/fleet/osqueryd.results.log

    vulnerabilities:
      current_instance_checks: true
      databases_path: /var/lib/fleet/vulndb
  '';

  # Prepare Fleet database
  systemd.services.fleetdm-prepare-db = {
    description = "Prepare FleetDM database";

    after = [
      "mysql.service"
    ];

    requires = [
      "mysql.service"
    ];

    serviceConfig = {
      Type = "oneshot";
      User = "fleet";
      Group = "fleet";
      StateDirectory = "fleet";
    };

    script = ''
      ${fleet}/bin/fleet prepare db --no-prompt --config /etc/fleet/fleet.yml
    '';
  };

  # Fleet server
  systemd.services.fleetdm = {
    description = "FleetDM server";

    wantedBy = [ "multi-user.target" ];

    after = [
      "network-online.target"
      "mysql.service"
      "redis-fleet.service"
      "fleetdm-prepare-db.service"
    ];

    wants = [
      "network-online.target"
    ];

    requires = [
      "mysql.service"
      "redis-fleet.service"
      "fleetdm-prepare-db.service"
    ];

    serviceConfig = {
      User = "fleet";
      Group = "fleet";

      EnvironmentFile = [ config.sops.templates."fleet-env".path ];

      ExecStart = "${fleet}/bin/fleet serve --config /etc/fleet/fleet.yml";

      Restart = "on-failure";
      RestartSec = "5s";

      StateDirectory = "fleet";
      LogsDirectory = "fleet";
      RuntimeDirectory = "fleet";

      # hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      PrivateDevices = true;
      ProtectClock = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
    };

    restartTriggers = [
      config.environment.etc."fleet/fleet.yml".source
    ];
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString fleetPort}";
      proxyWebsockets = true;

      extraConfig = ''
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        client_max_body_size 100m;
      '';
    };
  };
}
