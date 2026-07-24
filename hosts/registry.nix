# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  cfg = config.services.zot-registry;
  inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) zot;

  zotDataDir = "/var/lib/zot";
  zotPort = 443;
  acmeDirectory = config.security.acme.certs.${cfg.domain}.directory;

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
      address = "0.0.0.0";
      port = zotPort;
      externalUrl = "https://${cfg.domain}";
      tls = {
        cert = "${acmeDirectory}/fullchain.pem";
        key = "${acmeDirectory}/key.pem";
      };

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

    networking.firewall.allowedTCPPorts = [
      80
      zotPort
    ];

    security.acme = {
      acceptTerms = true;
      defaults.email = "trash@unikie.com";
      certs.${cfg.domain} = {
        group = "zot";
        listenHTTP = ":80";
        reloadServices = [ "zot.service" ];
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
      after = [
        "acme-${cfg.domain}.service"
        "network-online.target"
      ];
      wants = [
        "acme-${cfg.domain}.service"
        "network-online.target"
      ];

      serviceConfig = {
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
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
