# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  self,
  inputs,
  lib,
  config,
  machines,
  ...
}:
let
  sshified = pkgs.callPackage ../../pkgs/sshified/default.nix { };

  # populates known hosts as well as grafana scrape targets
  sshMonitoredHosts = {
    inherit (machines)
      ghaf-log
      ghaf-proxy
      ghaf-auth
      hetzarm
      hetz86-1
      hetz86-builder
      hetzci-dev
      hetzci-prod
      ;
  };

  domain = "monitoring.vedenemo.dev";

in
{
  imports =
    [
      ./disk-config.nix
      inputs.sops-nix.nixosModules.sops
      inputs.disko.nixosModules.disko
    ]
    ++ (with self.nixosModules; [
      common
      qemu-common
      ficolo-common
      service-openssh
      service-nginx
      team-devenv
    ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      sshified_private_key.owner = "sshified";
      metrics_basic_auth.owner = "nginx";

      # github oauth app credentials
      github_client_id.owner = "grafana";
      github_client_secret.owner = "grafana";
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking.hostName = "monitoring";

  users.users."sshified".isNormalUser = true;

  # add public keys of hosts we monitor through ssh
  services.openssh.knownHosts = lib.mapAttrs (_: host: {
    hostNames = [ host.ip ];
    inherit (host) publicKey;
  }) sshMonitoredHosts;

  # runs a tiny webserver on port 8888 that tunnels requests through ssh connection
  systemd.services."sshified" = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    description = "Run the sshified http-to-ssh proxy";
    serviceConfig = {
      User = "sshified";
      ExecStart = ''
        ${sshified}/bin/sshified \
        --proxy.listen-addr 127.0.0.1:8888 \
        --ssh.user sshified \
        --ssh.key-file ${config.sops.secrets.sshified_private_key.path} \
        --ssh.known-hosts-file /etc/ssh/sshified_known_hosts \
        --ssh.port 22 \
        -v
      '';
    };
  };

  systemd.paths."restart-sshified-on-hosts-change" = {
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = "/etc/ssh/sshified_known_hosts";
    };
  };

  systemd.services."restart-sshified-on-hosts-change" = {
    script = ''
      systemctl restart sshified.service
    '';
    serviceConfig = {
      Type = "oneshot";
    };
  };

  services.monitoring = {
    metrics.enable = true;
    logs = {
      enable = true;
      lokiAddress = "http://${config.services.loki.configuration.server.http_listen_address}:${toString config.services.loki.configuration.server.http_listen_port}";
    };
  };

  services.grafana = {
    enable = true;

    settings = {
      server = {
        http_port = 3000;
        http_addr = "127.0.0.1";
        inherit domain;
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
        allowed_organizations = [ "tiiuae" ];
        allow_assign_grafana_admin = true;
        team_ids = "7362549"; # devenv-fi
        role_attribute_path = "contains(groups[*], '@tiiuae/devenv-fi') && 'GrafanaAdmin'";
      };

      # disable username/password auth
      auth.disable_login_form = true;
    };

    provision.datasources.settings.datasources = [
      {
        name = "prometheus";
        type = "prometheus";
        isDefault = true;
        url = "http://${config.services.prometheus.listenAddress}:${toString config.services.prometheus.port}/prometheus";
      }
      {
        name = "loki";
        type = "loki";
        url = "http://${config.services.loki.configuration.server.http_listen_address}:${toString config.services.loki.configuration.server.http_listen_port}";
      }
    ];
  };

  services.loki = {
    enable = true;

    configuration = {
      auth_enabled = false;
      server = {
        http_listen_port = 3100;
        http_listen_address = "127.0.0.1";
      };

      common = {
        path_prefix = config.services.loki.dataDir;
        storage.filesystem = {
          chunks_directory = "${config.services.loki.dataDir}/chunks";
          rules_directory = "${config.services.loki.dataDir}/rules";
        };
        replication_factor = 1;
        ring.kvstore.store = "inmemory";
        ring.instance_addr = "127.0.0.1";
      };

      schema_config.configs = [
        {
          from = "2020-11-08";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          index.prefix = "index_";
          index.period = "24h";
        }
      ];

      query_range.cache_results = true;
    };
  };

  services.prometheus = {
    enable = true;

    port = 9090;
    listenAddress = "0.0.0.0";
    webExternalUrl = "/prometheus/";
    checkConfig = true;
    globalConfig.scrape_interval = "15s";

    # blackbox exporter can ping abritrary urls for us
    exporters.blackbox = {
      enable = true;
      listenAddress = "127.0.0.1";
      configFile = pkgs.writeText "probes.yml" (
        builtins.toJSON {
          modules.https_success = {
            prober = "http";
            tcp.tls = true;
            http.headers.User-Agent = "blackbox-exporter";
          };
        }
      );
    };

    pushgateway = {
      enable = true;
      web = {
        external-url = "https://${domain}/push/";
        listen-address = "127.0.0.1:9091";
      };
    };

    scrapeConfigs = [
      {
        job_name = "ficolo-internal-monitoring";
        static_configs =
          lib.mapAttrsToList
            (name: value: {
              targets = [ "${value.ip}:9100" ];
              labels = {
                machine_name = name;
              };
            })
            {
              inherit (machines)
                build1
                build2
                build3
                build4
                monitoring
                ;
            };
      }
      {
        job_name = "ssh-monitoring";
        # proxy the requests through our ssh tunnel
        proxy_url = "http://127.0.0.1:8888";
        static_configs = lib.mapAttrsToList (name: value: {
          targets = [ "${value.ip}:9100" ];
          labels = {
            machine_name = name;
          };
        }) sshMonitoredHosts;
      }
      {
        job_name = "blackbox";
        metrics_path = "/probe";
        params.module = [ "https_success" ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "instance";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "machine_name";
          }
          {
            target_label = "__address__";
            replacement = "127.0.0.1:9115";
          }
        ];
        static_configs = [
          {
            targets = [ "ci-prod.vedenemo.dev" ];
            labels = {
              env = "prod";
            };
          }
          {
            targets = [ "ci-dev.vedenemo.dev" ];
            labels = {
              env = "dev";
            };
          }
        ];
      }
      {
        job_name = "pushgateway";
        metrics_path = "/push/metrics";
        honor_labels = true;
        static_configs = [
          {
            targets = [ "127.0.0.1:9091" ];
          }
        ];
      }
    ];
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "trash@unikie.com";
  };

  services.nginx.virtualHosts =
    let
      grafana = {
        proxyPass = "http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}";
        proxyWebsockets = true;
      };
      loki = {
        proxyPass = "http://127.0.0.1:${toString config.services.loki.configuration.server.http_listen_port}/loki";
        proxyWebsockets = true;
      };
      prometheus = {
        proxyPass = "http://127.0.0.1:${toString config.services.prometheus.port}";
        proxyWebsockets = true;
      };
    in
    {
      "${domain}" = {
        default = true;
        enableACME = true;
        forceSSL = true;
        locations = {
          "/" = grafana;
          "/loki" = loki // {
            basicAuthFile = config.sops.secrets.metrics_basic_auth.path;
          };
          "/push/" = {
            proxyPass = "http://${config.services.prometheus.pushgateway.web.listen-address}";
            proxyWebsockets = true;
            basicAuthFile = config.sops.secrets.metrics_basic_auth.path;
          };
          "/prometheus/" = prometheus // {
            basicAuthFile = config.sops.secrets.metrics_basic_auth.path;
          };
        };
      };

      # no auth required when accessing through internal ip address
      "${machines.monitoring.ip}" = {
        locations = {
          "/" = grafana;
          "/loki" = loki;
          "/prometheus/" = prometheus;
        };
      };
    };
}
