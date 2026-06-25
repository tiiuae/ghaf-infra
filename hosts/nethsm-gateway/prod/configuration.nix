# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  machines,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ../common.nix
  ];

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      nebula-cert.owner = config.nebula.user;
      nebula-key.owner = config.nebula.user;
    };
  };

  networking.hostName = "nethsm-gateway";

  # NetHSM connected directly to the ethernet port
  networking.interfaces.enp89s0 = {
    ipv4.addresses = [
      {
        address = "10.255.255.2";
        prefixLength = 29;
      }
    ];
  };

  pkcs11.proxy.listenAddr = machines.nethsm-gateway.nebula_ip;

  nebula = {
    enable = true;
    cert = config.sops.secrets.nebula-cert.path;
    key = config.sops.secrets.nebula-key.path;
  };

  services.nebula.networks."vedenemo".firewall = {
    outbound = lib.mkForce [
      # allow udp outbound only to hetzner
      {
        port = 4242;
        proto = "udp";
        groups = [ "hetzner" ];
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

}
