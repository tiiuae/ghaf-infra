# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.hetzci.auth;
in
{
  options.hetzci.auth = {
    domain = lib.mkOption {
      type = lib.types.str;
      description = "Public address of this instance without protocol";
    };

    clientID = lib.mkOption {
      type = lib.types.str;
    };
  };
  config = {
    sops = {
      secrets = {
        oauth2_proxy_client_secret.owner = "oauth2-proxy";
        oauth2_proxy_cookie_secret.owner = "oauth2-proxy";
      };
      templates.oauth2_proxy_env = {
        content = ''
          OAUTH2_PROXY_COOKIE_SECRET=${config.sops.placeholder.oauth2_proxy_cookie_secret}
        '';
        owner = "oauth2-proxy";
      };
    };

    services.oauth2-proxy = {
      enable = true;
      inherit (cfg) clientID;
      clientSecret = null;
      cookie.secret = null;
      provider = "oidc";
      oidcIssuerUrl = "https://auth.vedenemo.dev";
      setXauthrequest = true;
      cookie.secure = false;
      extraConfig = {
        email-domain = "*";
        auth-logging = true;
        request-logging = true;
        standard-logging = true;
        reverse-proxy = true;
        scope = "openid profile email groups offline_access";
        cookie-expire = "168h";
        cookie-refresh = "24h";
        skip-provider-button = true;
        client-secret-file = config.sops.secrets.oauth2_proxy_client_secret.path;
        whitelist-domain = cfg.domain;
      };
      keyFile = config.sops.templates.oauth2_proxy_env.path;
    };

    systemd.services.oauth2-proxy = {
      # Try re-start at 10 second intervals
      serviceConfig.RestartSec = 10;
      # Allow unlimited restart attempts
      unitConfig.StartLimitBurst = 0;
    };

    services.caddy = {
      enable = true;
      enableReload = false;
      configFile = pkgs.writeText "Caddyfile" ''
        # Disable the admin API, we don't want to reconfigure Caddy at runtime.
        {
          admin off
        }

        https://${cfg.domain} {

          handle /login {
            redir * /
          }

          # Route /artifacts requests to caddy file_server
          handle_path /artifacts* {
            root * /var/lib/jenkins/artifacts
            file_server {
              browse
            }
          }

          @unauthenticated {
            # github sends webhook triggers here
            path /github-webhook /github-webhook/*

            # testagents need these
            path /jnlpJars /jnlpJars/*
            path /wsagents /wsagents/*
          }

          handle @unauthenticated {
            reverse_proxy localhost:8081
          }

          # Proxy all other requests to jenkins as-is, but delegate auth to
          # oauth2-proxy.
          # Also see https://oauth2-proxy.github.io/oauth2-proxy/configuration/integration#configuring-for-use-with-the-caddy-v2-forward_auth-directive

          handle /oauth2/* {
            reverse_proxy localhost:4180 {
              # oauth2-proxy requires the X-Real-IP and X-Forwarded-{Proto,Host,Uri} headers.
              # The reverse_proxy directive automatically sets X-Forwarded-{For,Proto,Host} headers.
              header_up X-Real-IP {remote_host}
              header_up X-Forwarded-Uri {uri}
            }
          }

          handle {
            forward_auth localhost:4180 {
              uri /oauth2/auth

              # oauth2-proxy requires the X-Real-IP and X-Forwarded-{Proto,Host,Uri} headers.
              # The forward_auth directive automatically sets the X-Forwarded-{For,Proto,Host,Method,Uri} headers.
              header_up X-Real-IP {remote_host}

              copy_headers {
                X-Auth-Request-User>X-Forwarded-User
                X-Auth-Request-Groups>X-Forwarded-Groups
                X-Auth-Request-Email>X-Forwarded-Mail
                X-Auth-Request-Preferred-Username>X-Forwarded-DisplayName
              }

              # If oauth2-proxy returns a 401 status, redirect the client to the sign-in page.
              @error status 401
              handle_response @error {
                redir * /oauth2/sign_in?rd={scheme}://{host}{uri}
              }
            }
            reverse_proxy localhost:8081
          }
        }
      '';
    };

    # Expose the HTTP[S] port. We still need HTTP for the HTTP-01 challenge.
    # While TLS-ALPN-01 could be used, disabling HTTP-01 seems only possible from
    # the JSON config, which won't work alongside Caddyfile.
    networking.firewall.allowedTCPPorts = [
      443
    ];
  };
}
