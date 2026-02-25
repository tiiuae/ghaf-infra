# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  config,
  inputs,
  ...
}:
let
  domain = "auth.vedenemo.dev";
in
{
  imports = [
    ./disk-config.nix
    ../hetzner-cloud.nix
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    service-nginx
    team-devenv
  ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      dex_env.owner = "dex";
    };
  };

  system.stateVersion = lib.mkForce "24.11";
  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "ghaf-auth";

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };

  services.dex = {
    enable = true;
    environmentFile = config.sops.secrets.dex_env.path;

    settings = {
      issuer = "https://${domain}";
      enablePasswordDB = false;

      storage = {
        type = "sqlite3";
        config.file = "/var/lib/dex/dex.db";
      };

      web.http = "127.0.0.1:5556";

      frontend = {
        issuer = "Vedenemo Auth";
        theme = "dark";
      };

      oauth2 = {
        skipApprovalScreen = false;
        alwaysShowLoginScreen = false;
      };

      connectors = [
        {
          type = "github";
          id = "github";
          name = "GitHub";
          config = {
            useLoginAsID = true;
            clientID = "$GITHUB_CLIENT_ID";
            clientSecret = "$GITHUB_CLIENT_SECRET";
            redirectURI = "https://${domain}/callback";
            orgs = [
              {
                name = "tiiuae";
                teams = [
                  "devenv-fi"
                  "phone"
                ];
              }
            ];
            teamNameField = "slug";
          };
        }
      ];

      expiry = {
        idTokens = "24h";
        refreshTokens.absoluteLifetime = "168h"; # 7 days
      };

      staticClients =
        let
          grantTypes = [
            "authorization_code"
            "refresh_token"
          ];
        in
        [
          {
            id = "zot-registry";
            name = "registry.vedenemo.dev";
            redirectURIs = [ "https://registry.vedenemo.dev/zot/auth/callback/oidc" ];
            secretEnv = "ZOT_CLIENT_SECRET";
            inherit grantTypes;
          }
          {
            id = "hetzci-dbg";
            name = "ci-dbg.vedenemo.dev";
            redirectURIs = [ "https://ci-dbg.vedenemo.dev/oauth2/callback" ];
            secretEnv = "CI_DBG_CLIENT_SECRET";
            inherit grantTypes;
          }
          {
            id = "hetzci-dev";
            name = "ci-dev.vedenemo.dev";
            redirectURIs = [ "https://ci-dev.vedenemo.dev/oauth2/callback" ];
            secretEnv = "CI_DEV_CLIENT_SECRET";
            inherit grantTypes;
          }
          {
            id = "hetzci-prod";
            name = "ci-prod.vedenemo.dev";
            redirectURIs = [ "https://ci-prod.vedenemo.dev/oauth2/callback" ];
            secretEnv = "CI_PROD_CLIENT_SECRET";
            inherit grantTypes;
          }
          {
            id = "hetzci-release";
            name = "ci-release.vedenemo.dev";
            redirectURIs = [ "https://ci-release.vedenemo.dev/oauth2/callback" ];
            secretEnv = "CI_RELEASE_CLIENT_SECRET";
            inherit grantTypes;
          }
          {
            id = "azureci-prod";
            name = "ci-prod.uaenorth.cloudapp.azure.com";
            redirectURIs = [
              "https://ci-prod.uaenorth.cloudapp.azure.com/oauth2/callback"
            ];
            secretEnv = "UAE_CI_PROD_CLIENT_SECRET";
            inherit grantTypes;
          }
          {
            id = "ghaf-jenkins-controller-northeurope";
            name = "ghaf-jenkins-controller-release.northeurope.cloudapp.azure.com";
            redirectURIs = [
              "https://ghaf-jenkins-controller-release.northeurope.cloudapp.azure.com/oauth2/callback"
            ];
            secretEnv = "AZURE_CI_RELEASE_CLIENT_SECRET";
            inherit grantTypes;
          }
        ];
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

  services.nginx.virtualHosts = {
    "auth.vedenemo.dev" = {
      enableACME = true;
      forceSSL = true;
      default = true;
      locations."/" = {
        proxyPass = "http://${config.services.dex.settings.web.http}";
      };
    };
  };
}
