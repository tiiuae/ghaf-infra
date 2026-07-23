# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  config,
  lib,
  machines,
  pkgs,
  self,
  ...
}:
let
  cfg = config.services.zot-registry;
  inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) zot;

  zotDataDir = "/var/lib/zot";
  zotPort = 5000;
  isS3Storage = (cfg.storageConfig.storageDriver.name or null) == "s3";

  zotConfig = {
    storage = {
      rootDirectory = zotDataDir;
      dedupe = false;
      gc = true;
      gcInterval = "1h";
      retention = {
        delay = "24h";
        policies = [
          {
            repositories = [ "ghaf/**" ];
            deleteReferrers = true;
            deleteUntagged = true;
            keepTags = [
              {
                patterns = [
                  ".*-latest"
                  "ghaf-.*"
                ];
              }
              {
                patterns = [ "release-.*" ];
                # Keep at least three builds in each repository
                mostRecentlyPushedCount = 3;
                # Keep everything for at least a week
                pushedWithin = "168h";
              }
              {
                patterns = [ "prod-.*" ];
                mostRecentlyPushedCount = 3;
                pushedWithin = "168h";
              }
              {
                patterns = [ "dev-.*" ];
                mostRecentlyPushedCount = 3;
                pushedWithin = "168h";
              }
              {
                patterns = [
                  "vm-.*"
                  "dbg-.*"
                ];
                pushedWithin = "24h";
              }
            ];
          }
        ];
      };
    }
    // cfg.storageConfig;

    http = {
      address = "127.0.0.1";
      port = zotPort;
      externalUrl = "https://${cfg.domain}";

      auth = {
        htpasswd.path = config.sops.secrets.zot-htpasswd.path;
        apikey = true;
        openid.providers.oidc = {
          name = "Vedenemo Auth";
          issuer = "https://auth.vedenemo.dev";
          credentialsFile = config.sops.templates."zot-oidc-credentials.json".path;
          keypath = "";
          scopes = [
            "openid"
            "profile"
            "email"
            "groups"
          ];
        };
      };

      accessControl = {
        repositories = {
          "ghaf/**" = {
            policies = [
              {
                users = [ "jenkins" ];
                actions = [
                  "read"
                  "create"
                  "update"
                  "delete"
                ];
              }
            ];
            defaultPolicy = [ "read" ];
            anonymousPolicy = [ "read" ];
          };
          "**" = {
            defaultPolicy = [
              "read"
              "create"
              "update"
              "delete"
            ];
            anonymousPolicy = [ "read" ];
          };
        };
      }
      // lib.optionalAttrs cfg.metrics.enable {
        metrics.users = [ "prometheus" ];
      };
    };
    log.level = "warn";
    extensions = {
      ui.enable = true;
      search.enable = true;
      metrics.enable = cfg.metrics.enable;
    };
  };
  zotConfigFile = pkgs.writeText "zot_config.json" (builtins.toJSON zotConfig);
in
{
  options.services.zot-registry = {
    clientId = lib.mkOption {
      type = lib.types.str;
      description = "OIDC client ID used by the registry.";
    };
    domain = lib.mkOption {
      type = lib.types.str;
      description = "Public registry domain.";
    };
    storageConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Site-specific Zot storage configuration.";
    };
    metrics.enable = lib.mkEnableOption "Zot metrics";
  };

  config = {
    sops = {
      secrets = {
        auth-client-secret.owner = "zot";
        zot-s3-credentials.owner = "zot";
        zot-htpasswd.owner = "zot";
      };
      templates."zot-oidc-credentials.json" = {
        owner = "zot";
        content = builtins.toJSON {
          clientid = cfg.clientId;
          clientsecret = config.sops.placeholder.auth-client-secret;
        };
      };
    };

    services.nginx.virtualHosts.${cfg.domain} = {
      enableACME = true;
      forceSSL = true;
      default = true;
      http2 = lib.mkIf isS3Storage false;

      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString zotPort}";
        # nginx buffering causes pulls to fail occasionally when using s3 backend
        extraConfig = ''
          client_max_body_size 0;
          proxy_buffering off;
          proxy_request_buffering off;
          proxy_max_temp_file_size 0;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
          client_body_timeout 3600s;
        '';
      };

      locations."/metrics" = lib.mkIf cfg.metrics.enable {
        proxyPass = "http://127.0.0.1:${toString zotPort}/metrics";
        extraConfig = ''
          allow ${machines.ghaf-monitoring.internal_ip};
          deny all;
        '';
      };
    };

    users.groups.zot = { };
    users.users.zot = {
      isSystemUser = true;
      group = "zot";
      home = zotDataDir;
      createHome = true;
    };

    systemd.tmpfiles.rules = [
      "d ${zotDataDir} 0750 zot zot - -"
    ];

    systemd.services.zot = {
      description = "zot OCI registry";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        User = "zot";
        Group = "zot";
        ExecStart = "${zot}/bin/zot serve ${zotConfigFile}";
        Restart = "always";
        RestartSec = "5s";
        UMask = "0027";
        EnvironmentFile = config.sops.secrets.zot-s3-credentials.path;
        WorkingDirectory = zotDataDir;
        ReadWritePaths = [ zotDataDir ];
      };
    };
  };
}
