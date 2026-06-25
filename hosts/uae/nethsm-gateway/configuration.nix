# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  config,
  machines,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ../../nethsm-gateway/common.nix
    self.nixosModules.user-bmg
  ];

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      nebula-cert.owner = config.nebula.user;
      nebula-key.owner = config.nebula.user;
    };
  };

  networking.hostName = "uae-nethsm-gateway";

  # Assign IP configs because dhcp is disabled in network
  networking = {
    interfaces.enp3s0 = {
      ipv4.addresses = [
        {
          address = "172.31.141.51";
          prefixLength = 24;
        }
      ];
    };
    interfaces.eno1 = {
      ipv4.addresses = [
        {
          address = "192.168.70.2";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "172.31.141.1";
      interface = "enp3s0";
    };
    nameservers = [
      "10.161.10.11"
      "10.161.10.12"
    ];
  };

  nethsm.host = "192.168.70.20";
  pkcs11.proxy.listenAddr = machines.uae-nethsm-gateway.nebula_ip;

  nebula = {
    enable = true;
    cert = config.sops.secrets.nebula-cert.path;
    key = config.sops.secrets.nebula-key.path;
  };

  services.nebula.networks."vedenemo".firewall = {
    outbound = lib.mkForce [
      # allow udp outbound only to hetzner, uae-lab and azureci
      {
        port = 4242;
        proto = "udp";
        groups = [
          "hetzner"
        ];
      }
      # allow dns requests
      {
        port = 53;
        proto = "udp";
        host = "any";
      }
      # allow any tcp or icmp outbound (between nebula hosts)
      {
        port = "any";
        proto = "tcp";
        host = "any";
      }
      {
        port = "any";
        proto = "icmp";
        host = "any";
      }
    ];
    inbound = [
      # allow monitoring server to scrape nethsm metrics
      {
        inherit (config.nethsm.exporter) port;
        proto = "tcp";
        groups = [ "scraper" ];
      }
      # pkcs11-daemon
      {
        port = config.pkcs11.proxy.listenPort;
        proto = "tcp";
        host = "any";
      }
    ];
  };

  services.nebula.networks."vedenemo".staticHostMap = {
    "10.42.42.35" = [ "213.42.107.24:4242" ];
  };
}
