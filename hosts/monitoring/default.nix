# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  config,
  ...
}: let
  # "public" but really only available with ficolo vpn
  public-ip = "172.18.20.108";
in {
  imports = lib.flatten [
    (with inputs; [
      nix-serve-ng.nixosModules.default
      disko.nixosModules.disko
    ])
    (with self.nixosModules; [
      common
      qemu-common
      service-openssh
      service-nginx
      service-node-exporter
      user-jrautiola
    ])
    ./disk-config.nix
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  networking = {
    hostName = "monitoring";
    nameservers = ["1.1.1.1" "8.8.8.8"];
    firewall = {
      allowedTCPPorts = [config.services.prometheus.port config.services.grafana.settings.server.http_port];
      allowedUDPPorts = [config.services.prometheus.port config.services.grafana.settings.server.http_port];
    };
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

    scrapeConfigs = [
      {
        job_name = "ficolo-node-exporter";
        static_configs = [
          {
            targets = [
              "172.18.20.109:9002" # binarycache
              "172.18.20.105:9999" # build4
            ];
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
