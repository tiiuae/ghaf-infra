# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  config,
  inputs,
  ...
}:
{
  imports = [
    ./disk-config.nix
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    hetzner-cloud
    common
    openssh
    nginx
    auth-server
    team-devenv
  ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      dex_env.owner = "dex";
    };
  };

  system.stateVersion = lib.mkForce "24.11";
  networking.hostName = "ghaf-auth";

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };

  services.auth-server = {
    enable = true;
    domain = "auth.vedenemo.dev";
    environmentFile = config.sops.secrets.dex_env.path;

    github.settings.orgs = [
      {
        name = "tiiuae";
        teams = [
          "devenv-fi"
          "phone"
          "ci-dev-admins"
        ];
      }
    ];

    settings = {
      frontend.issuer = "Vedenemo Auth";

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
            id = "azureci-dev";
            name = "ci-dev.uaenorth.cloudapp.azure.com";
            redirectURIs = [ "https://ci-dev.uaenorth.cloudapp.azure.com/oauth2/callback" ];
            secretEnv = "UAE_CI_DEV_CLIENT_SECRET";
            inherit grantTypes;
          }
          {
            id = "uae-zot-registry";
            name = "registry.uaenorth.cloudapp.azure.com";
            redirectURIs = [ "https://registry.uaenorth.cloudapp.azure.com/zot/auth/callback/oidc" ];
            secretEnv = "UAE_ZOT_CLIENT_SECRET";
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

  services.nginx.virtualHosts.${config.services.auth-server.domain} = {
    enableACME = true;
    forceSSL = true;
    default = true;
  };
}
