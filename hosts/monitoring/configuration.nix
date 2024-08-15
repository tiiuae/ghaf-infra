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
  sops.secrets.sshified_private_key.owner = "sshified";

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
      service-node-exporter
      user-jrautiola
      user-karim
    ]);

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  networking = {
    hostName = "monitoring";
    firewall = {
      allowedTCPPorts = [
        config.services.prometheus.port
        config.services.grafana.settings.server.http_port
      ];
      allowedUDPPorts = [
        config.services.prometheus.port
        config.services.grafana.settings.server.http_port
      ];
    };
  };

  users.users."sshified".isNormalUser = true;

  services.openssh.knownHosts = {
    "65.21.20.242".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILx4zU4gIkTY/1oKEOkf9gTJChdx/jR3lDgZ7p/c7LEK";
    "95.217.177.197".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICMmB3Ws5MVq0DgVu+Hth/8NhNAYEwXyz4B6FRCF6Nu2";
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

  services.grafana = {
    enable = true;

    settings = {
      server = {
        http_port = 3000;
        http_addr = "127.0.0.1";
      };

      # disable telemetry
      analytics = {
        reporting_enabled = false;
        feedback_links_enabled = false;
      };

      # allow read-only access to dashboards without login
      # this is fine because the page is only accessible with vpn
      "auth.anonymous".enabled = true;
    };

    provision.datasources.settings.datasources = [
      {
        name = "prometheus";
        type = "prometheus";
        isDefault = true;
        url = "http://${config.services.prometheus.listenAddress}:${toString config.services.prometheus.port}";
      }
    ];
  };

  services.prometheus = {
    enable = true;

    port = 9090;
    listenAddress = "0.0.0.0";
    webExternalUrl = "http://${public-ip}:${toString config.services.prometheus.port}";
    checkConfig = true;

    globalConfig.scrape_interval = "15s";

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
          {
            targets = [ "172.18.20.109:9100" ];
            labels = {
              machine_name = "binarycache";
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
        ];
      }
    ];
  };

  services.nginx = {
    virtualHosts = {
      "_" = {
        default = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}";
          proxyWebsockets = true;
        };
      };
    };
  };
}
