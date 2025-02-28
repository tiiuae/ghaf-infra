# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  modulesPath,
  lib,
  config,
  ...
}:
{
  imports =
    [
      ./disk-config.nix
      (modulesPath + "/profiles/qemu-guest.nix")
      inputs.sops-nix.nixosModules.sops
      inputs.disko.nixosModules.disko
      ./loki.nix
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
      service-nginx
      service-monitoring
      user-jrautiola
      user-cazfi
      user-hrosten
      user-ktu
      user-bmg
      user-vunnyso
    ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      # basic auth credentials generated with htpasswd
      loki_basic_auth.owner = "nginx";
      # github oauth app credentials
      github_client_id.owner = "grafana";
      github_client_secret.owner = "grafana";
      # vedenemo monitoring
      vedenemo_loki_password.owner = "promtail";
    };
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "ghaf-log";
    useDHCP = true;
  };

  boot = {
    # use predictable network interface names (eth0)
    kernelParams = [ "net.ifnames=0" ];
    loader.grub = {
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
  };

  # this server has been reinstalled with 24.05
  system.stateVersion = lib.mkForce "24.05";

  services.monitoring = {
    metrics = {
      enable = true;
      ssh = true;
    };
    logs = {
      enable = true;
      lokiAddress = "https://monitoring.vedenemo.dev";
      auth.password_file = config.sops.secrets.vedenemo_loki_password.path;
    };
  };

  # Grafana
  services.grafana = {
    enable = true;

    settings = {
      server = {
        http_port = 3000;
        http_addr = "127.0.0.1";
        domain = "ghaflogs.vedenemo.dev";
        enforce_domain = true;

        # the default root_url is unaware of our nginx reverse proxy,
        # and tries using http with port 3000 as the redirect url for auth.
        # https://github.com/grafana/grafana/issues/11817#issuecomment-387131608
        root_url = "https://%(domain)s/";
      };

      # disable telemetry
      analytics = {
        reporting_enabled = false;
        feedback_links_enabled = false;
      };

      # https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-security-hardening
      security = {
        cookie_secure = true;
        # we cannot use 'strict' here or github oauth cannot set the login cookie
        cookie_samesite = "lax";
        login_cookie_name = "__Host-grafana_session";
        strict_transport_security = true;
      };

      # github OIDC
      "auth.github" = {
        enabled = true;
        client_id = "$__file{${config.sops.secrets.github_client_id.path}}";
        client_secret = "$__file{${config.sops.secrets.github_client_secret.path}}";

        # only these orgs and teams are allowed login
        # team IDs can be found with github api:
        # $ curl -H "Authorization: $PAT" "https://api.github.com/orgs/tiiuae/teams?per_page=100" | jq '.[] | {name, id}'
        allowed_organizations = [ "tiiuae" ];
        team_ids = lib.strings.concatStringsSep "," [
          "7362549" # devenv-fi
          "4067903" # phone
        ];

        # map github teams to grafana roles
        role_attribute_path = lib.strings.concatStringsSep " || " [
          "contains(groups[*], '@tiiuae/devenv-fi') && 'GrafanaAdmin'"
          "contains(groups[*], '@tiiuae/phone') && 'Editor'"
        ];
      };
    };

    provision.datasources.settings.datasources = [
      {
        name = "loki";
        type = "loki";
        isDefault = true;
        url = "http://${config.services.loki.configuration.server.http_listen_address}:${toString config.services.loki.configuration.server.http_listen_port}";
      }
    ];
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "trash@unikie.com";
  };

  services.nginx = {
    virtualHosts = {
      "${config.services.grafana.settings.server.domain}" = {
        enableACME = true;
        forceSSL = true;
        default = true;
        locations."/" = {
          proxyPass = "http://${config.services.grafana.settings.server.http_addr}:${toString config.services.grafana.settings.server.http_port}";
          proxyWebsockets = true;
        };
      };

      "loki.${config.services.grafana.settings.server.domain}" = {
        enableACME = true;
        forceSSL = true;
        basicAuthFile = config.sops.secrets.loki_basic_auth.path;
        locations."/" = {
          proxyPass = "http://${config.services.loki.configuration.server.http_listen_address}:${toString config.services.loki.configuration.server.http_listen_port}";
          proxyWebsockets = true;
        };
      };
    };
  };
}
