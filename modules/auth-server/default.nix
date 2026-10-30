# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.auth-server;
  defaultSettings = {
    issuer = cfg.issuer;
    enablePasswordDB = false;
    storage = {
      type = "sqlite3";
      config = lib.optionalAttrs ((cfg.settings.storage.type or "sqlite3") == "sqlite3") {
        file = "/var/lib/dex/dex.db";
      };
    };
    web.http = cfg.listenAddress;
    frontend = {
      issuer = "Ghaf Auth";
      theme = "dark";
    };
    oauth2 = {
      skipApprovalScreen = false;
      alwaysShowLoginScreen = false;
    };
    connectors = lib.optional cfg.github.enable {
      type = "github";
      id = "github";
      name = "GitHub";
      config = lib.recursiveUpdate {
        useLoginAsID = true;
        clientID = "$GITHUB_CLIENT_ID";
        clientSecret = "$GITHUB_CLIENT_SECRET";
        redirectURI = "${lib.removeSuffix "/" (cfg.settings.issuer or cfg.issuer)}/callback";
        teamNameField = "slug";
      } cfg.github.settings;
    };
    expiry = {
      idTokens = "24h";
      refreshTokens.absoluteLifetime = "168h";
    };
  };
in
{
  options.services.auth-server = {
    enable = lib.mkEnableOption "the Ghaf Dex OIDC authentication server";

    package = lib.mkPackageOption pkgs "dex-oidc" { };

    domain = lib.mkOption {
      type = lib.types.str;
      example = "auth.example.org";
      description = "Authentication server hostname, used for nginx and the default issuer URL.";
    };

    issuer = lib.mkOption {
      type = lib.types.str;
      default = "https://${cfg.domain}";
      defaultText = lib.literalExpression ''"https://''${config.services.auth-server.domain}"'';
      example = "https://auth.example.org";
      description = "Public OIDC issuer URL, including any path prefix.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:5556";
      description = "Address and port for Dex's HTTP listener.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/dex-env";
      description = "Runtime environment file containing credentials referenced by Dex settings as $VARIABLE_NAME. ";
    };

    github = {
      enable = lib.mkEnableOption "the GitHub login connector" // {
        default = true;
      };
      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "GitHub connector configuration, recursively merged with the defaults.";
      };
    };

    nginx.enable = lib.mkEnableOption "the nginx reverse proxy" // {
      default = true;
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Extra Dex configuration, recursively merged with the defaults.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.dex = {
      enable = true;
      inherit (cfg) package environmentFile;
      settings = lib.recursiveUpdate defaultSettings cfg.settings;
    };

    services.nginx = lib.mkIf cfg.nginx.enable {
      enable = true;
      virtualHosts.${cfg.domain}.locations."/" = {
        proxyPass = "http://${config.services.dex.settings.web.http}";
        recommendedProxySettings = true;
      };
    };

    systemd.services.dex.serviceConfig = {
      StateDirectory = "dex";
      User = "dex";
      Group = "dex";
    };

    users.users.dex = {
      isSystemUser = true;
      group = "dex";
    };
    users.groups.dex = { };
  };
}
