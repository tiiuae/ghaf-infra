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

  zotConfig = lib.recursiveUpdate {
    storage = {
      rootDirectory = zotDataDir;
      dedupe = true;
      gc = true;
      gcInterval = "1h";
      gcDelay = "24h";
      retention = {
        policies = [
          {
            repositories = cfg.retention.repositories;
            deleteReferrers = true;
            deleteUntagged = true;
            keepTags = [
              {
                patterns = cfg.retention.keepTagPatterns;
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
    };

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
        sessionKeysFile = config.sops.templates."zot-session-keys.json".path;
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
          "**" = {
            defaultPolicy = [
              "read"
              "create"
              "update"
              "delete"
            ];
            anonymousPolicy = [ ];
          };
        }
        //
          lib.genAttrs (lib.unique (builtins.attrNames cfg.repositoryWriters ++ cfg.publicRepositories))
            (repository: {
              policies = lib.optional (builtins.hasAttr repository cfg.repositoryWriters) {
                users = cfg.repositoryWriters.${repository};
                actions = [
                  "read"
                  "create"
                  "update"
                  "delete"
                ];
              };
              defaultPolicy = [ "read" ];
              anonymousPolicy = lib.optionals (builtins.elem repository cfg.publicRepositories) [ "read" ];
            });
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
  } cfg.extraConfig;
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
    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional Zot configuration merged with the defaults.";
    };
    retention = {
      repositories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "ghaf/**" ];
        description = "Repository glob patterns to which the retention policy applies.";
      };
      keepTagPatterns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          ".*-latest"
          "ghaf-.*"
        ];
        description = "Tag regular expressions to retain indefinitely in repositories covered by the retention policy.";
      };
    };
    publicRepositories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Repository glob patterns that allow anonymous reads. Other repositories require authentication.";
    };
    repositoryWriters = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = {
        "ghaf/**" = [ "jenkins" ];
      };
      description = "Repository glob patterns mapped to users allowed to read, create, update, and delete images. Other authenticated users have read access to these repositories.";
    };
    metrics.enable = lib.mkEnableOption "Zot metrics";
  };

  config = {
    sops = {
      secrets = {
        auth-client-secret.owner = "zot";
        zot-htpasswd.owner = "zot";
        zot-hashkey.owner = "zot";
      };
      templates."zot-oidc-credentials.json" = {
        owner = "zot";
        content = builtins.toJSON {
          clientid = cfg.clientId;
          clientsecret = config.sops.placeholder.auth-client-secret;
        };
      };
      templates."zot-session-keys.json" = {
        owner = "zot";
        content = builtins.toJSON {
          hashKey = config.sops.placeholder.zot-hashkey;
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
        WorkingDirectory = zotDataDir;
        ReadWritePaths = [ zotDataDir ];
      };
    };
  };
}
