# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  self,
  lib,
  config,
  machines,
  inputs,
  ...
}:
let
  sshified = pkgs.callPackage ../../pkgs/sshified/default.nix { };
  domain = "monitoring.vedenemo.dev";
  volumeMount = config.disko.devices.disk.data.content.mountpoint;

  # populates known hosts as well as grafana scrape targets
  sshMonitoredHosts = {
    inherit (machines)
      hetzarm
      hetz86-1
      hetz86-builder
      ;
  };
in
{
  imports =
    [
      ./disk-config.nix
      ../hetzner-cloud.nix
      inputs.sops-nix.nixosModules.sops
      inputs.disko.nixosModules.disko
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
      service-nebula
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

      slack_webhook_url.owner = "grafana";

      nebula-cert.owner = config.nebula.user;
      nebula-key.owner = config.nebula.user;
    };
  };

  system.stateVersion = lib.mkForce "25.05";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking.hostName = "ghaf-monitoring";

  nebula = {
    enable = true;
    cert = config.sops.secrets.nebula-cert.path;
    key = config.sops.secrets.nebula-key.path;
  };

  users.users."sshified".isNormalUser = true;

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
        --ssh.known-hosts-file /etc/ssh/ssh_known_hosts \
        --ssh.port 22 \
        -v
      '';
    };
    restartTriggers = [ config.environment.etc."ssh/ssh_known_hosts".source ];
  };

  # add public keys of hosts we monitor through ssh
  services.openssh.knownHosts = lib.mapAttrs (_: host: {
    hostNames = [ host.ip ];
    inherit (host) publicKey;
  }) sshMonitoredHosts;

  # monitors also itself
  services.monitoring = {
    metrics.enable = true;
    logs = {
      enable = true;
      lokiAddress = "http://${config.services.loki.configuration.server.http_listen_address}:${toString config.services.loki.configuration.server.http_listen_port}";
    };
  };

  services.grafana = {
    enable = true;

    dataDir = volumeMount + "/grafana";

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
        allow_assign_grafana_admin = true;

        client_id = "$__file{${config.sops.secrets.github_client_id.path}}";
        client_secret = "$__file{${config.sops.secrets.github_client_secret.path}}";

        allowed_organizations = [ "tiiuae" ];
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
        uid = "prometheus";
        url = "http://${config.services.prometheus.listenAddress}:${toString config.services.prometheus.port}/prometheus";
        isDefault = true;
      }
      {
        name = "loki";
        type = "loki";
        uid = "loki";
        url = "http://${config.services.loki.configuration.server.http_listen_address}:${toString config.services.loki.configuration.server.http_listen_port}";
      }
    ];

    provision.dashboards.settings.providers =
      let
        # helper function for dashboards, src can take a local file or the output of fetchDashboard.
        # also takes an attrset of strings to replace, useful to declare the datasource IDs
        dashboard =
          {
            name,
            src,
            replacements ? { },
          }:
          {
            inherit name;
            options.path = pkgs.writeText "${name}.json" (
              builtins.replaceStrings (builtins.attrNames replacements) (builtins.attrValues replacements) (
                builtins.readFile src
              )
            );
          };

        # downloads dashboard json from https://grafana.com/grafana/dashboards/
        fetchDashboard =
          {
            id,
            version,
            hash,
          }:
          pkgs.fetchurl {
            inherit hash;
            name = "dashboard-${toString id}_rev${toString version}.json";
            url = "https://grafana.com/api/dashboards/${toString id}/revisions/${toString version}/download";
          };
      in
      [
        (dashboard {
          name = "node-exporter-full";
          src = fetchDashboard {
            hash = "sha256-fReu5M4+jrjiTN8kaM/2KPG5WYSe+H1z21T/Iv2JSuA=";
            id = 15172;
            version = 6;
          };
          replacements = {
            "\${DS_PROMETHEUS}" = "prometheus";
          };
        })
        (dashboard {
          name = "ssh-connections";
          src = ./provision/dashboards/ssh-connections.json;
          replacements = {
            "\${DS_LOKI}" = "loki";
          };
        })
      ];

    provision.alerting = {
      contactPoints.settings.contactPoints = [
        {
          name = "slack";
          receivers = [
            {
              uid = "1";
              type = "slack";
              settings = {
                text = ''{{ template "summary_only" . }}'';
                title = "Alert status";
                url = "$__file{${config.sops.secrets.slack_webhook_url.path}}";
              };
            }
          ];
        }
      ];
      policies.settings.policies = [
        {
          receiver = "slack";
          group_interval = "1m";
          group_by = [
            "grafana_folder"
            "alertname"
          ];
        }
      ];
      templates.settings.templates = [
        {
          name = "summary_only";
          template = ''
            {{- range .Alerts.Firing }} 
            🚨 {{ .Annotations.summary }}
            {{ end }}
            {{- range .Alerts.Resolved }} 
            ✅ {{ .Annotations.summary }}
            {{ end }}
          '';
        }
      ];

      rules.path = ./provision/alert-rules.yaml;
    };
  };

  services.loki = {
    enable = true;

    dataDir = volumeMount + "/loki";

    configuration = {
      auth_enabled = false;
      server = {
        http_listen_port = 3100;
        http_listen_address = "0.0.0.0";
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

  # Workaround for prometheus to store data outside of /var/lib
  # https://discourse.nixos.org/t/custom-prometheus-data-directory/50741/5
  systemd.tmpfiles.rules = [
    "D ${volumeMount}/prometheus 0751 prometheus prometheus - -"
    "L+ /var/lib/${config.services.prometheus.stateDir}/data - - - - ${volumeMount}/prometheus"
  ];

  services.prometheus = {
    enable = true;

    port = 9090;
    listenAddress = "127.0.0.1";
    webExternalUrl = "/prometheus/";
    checkConfig = true;
    retentionTime = "90d";
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
        job_name = "hetzner-cloud";
        static_configs =
          lib.mapAttrsToList
            (name: value: {
              targets = [ "${value.internal_ip}:9100" ];
              labels = {
                machine_name = name;
              };
            })
            {
              inherit (machines)
                ghaf-log
                ghaf-proxy
                ghaf-auth
                ghaf-monitoring
                ghaf-lighthouse
                hetzci-dev
                hetzci-prod
                hetzci-release
                ;
            };
      }
      {
        job_name = "hetzner-robot";
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
        job_name = "nebula";
        static_configs =
          map
            (name: {
              targets = [ "${name}.sumu.vedenemo.dev:9100" ];
              labels = {
                machine_name = name;
              };
            })
            [
              "testagent-dev"
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

  services.nginx.virtualHosts = {
    "${domain}" = {
      default = true;
      enableACME = true;
      forceSSL = true;

      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}";
        };
        "/loki" = {
          proxyPass = "http://127.0.0.1:${toString config.services.loki.configuration.server.http_listen_port}/loki";
          basicAuthFile = config.sops.secrets.metrics_basic_auth.path;
        };
        "/push/" = {
          proxyPass = "http://${config.services.prometheus.pushgateway.web.listen-address}";
          basicAuthFile = config.sops.secrets.metrics_basic_auth.path;
        };
        "/prometheus/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.prometheus.port}";
          basicAuthFile = config.sops.secrets.metrics_basic_auth.path;
        };
      };
    };
  };
}
