# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  self,
  inputs,
  lib,
  config,
  ...
}:
let
  # "public" but really only available with ficolo vpn
  public-ip = "172.18.20.108";
  sshified = pkgs.callPackage ../../pkgs/sshified/default.nix { };
in
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets = {
    sshified_private_key.owner = "sshified";
    loki_basic_auth.owner = "nginx";
    # github oauth app credentials
    github_client_id.owner = "grafana";
    github_client_secret.owner = "grafana";
  };

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
      user-jrautiola
    ]);

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  networking = {
    hostName = "monitoring";
    firewall = {
      allowedTCPPorts = [ config.services.prometheus.port ];
      allowedUDPPorts = [ config.services.prometheus.port ];
    };
  };

  users.users."sshified".isNormalUser = true;

  services.openssh.knownHosts = {
    "65.21.20.242".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILx4zU4gIkTY/1oKEOkf9gTJChdx/jR3lDgZ7p/c7LEK";
    "95.217.177.197".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICMmB3Ws5MVq0DgVu+Hth/8NhNAYEwXyz4B6FRCF6Nu2";
    "95.216.200.85".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIALs+OQDrCKRIKkwTwI4MI+oYC3RTEus9cXCBcIyRHzl";
  };

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
        domain = "monitoring.vedenemo.dev";
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
        url = "http://${config.services.prometheus.listenAddress}:${toString config.services.prometheus.port}";
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
    webExternalUrl = "http://${public-ip}:${toString config.services.prometheus.port}";
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

    scrapeConfigs = [
      {
        job_name = "ficolo-internal-monitoring";
        static_configs = [
          {
            targets = [ "172.18.20.102:9100" ];
            labels = {
              machine_name = "build1";
            };
          }
          {
            targets = [ "172.18.20.103:9100" ];
            labels = {
              machine_name = "build2";
            };
          }
          {
            targets = [ "172.18.20.104:9100" ];
            labels = {
              machine_name = "build3";
            };
          }
          {
            targets = [ "172.18.20.105:9100" ];
            labels = {
              machine_name = "build4";
            };
          }
          {
            targets = [ "172.18.20.106:9100" ];
            labels = {
              machine_name = "himalia";
            };
          }
          {
            targets = [ "172.18.20.107:9100" ];
            labels = {
              machine_name = "gerrit";
            };
          }
          {
            targets = [ "172.18.20.108:9100" ];
            labels = {
              machine_name = "monitoring";
            };
          }
        ];
      }
      {
        job_name = "ssh-monitoring";
        # proxy the requests through our ssh tunnel
        proxy_url = "http://127.0.0.1:8888";
        static_configs = [
          {
            targets = [ "65.21.20.242:9100" ];
            labels = {
              machine_name = "hetzarm";
            };
          }
          {
            targets = [ "95.217.177.197:9100" ];
            labels = {
              machine_name = "ghaf-log";
            };
          }
          {
            targets = [ "95.216.200.85:9100" ];
            labels = {
              machine_name = "ghaf-proxy";
            };
          }
        ];
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
            targets = [
              "ghaf-jenkins-controller-prod.northeurope.cloudapp.azure.com"
              "prod-cache.vedenemo.dev"
            ];
            labels = {
              env = "prod";
            };
          }
          {
            targets = [ "ghaf-jenkins-controller-dev.northeurope.cloudapp.azure.com" ];
            labels = {
              env = "dev";
            };
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
    in
    {
      "monitoring.vedenemo.dev" = {
        default = true;
        enableACME = true;
        forceSSL = true;
        locations = {
          "/" = grafana;
          "/loki" = loki // {
            basicAuthFile = config.sops.secrets.loki_basic_auth.path;
          };
        };
      };

      # no auth required when accessing through internal ip address
      "172.18.20.108" = {
        locations = {
          "/" = grafana;
          "/loki" = loki;
        };
      };
    };
}
