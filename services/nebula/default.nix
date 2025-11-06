# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  machines,
  lib,
  ...
}:
let
  cfg = config.nebula;

  networkName = "vedenemo";
  lighthouseAddress = "10.42.42.1";
  listenPort = 4242; # UDP port Nebula will use for sending/receiving traffic and for handshakes
  serviceUser = config.systemd.services."nebula@${networkName}".serviceConfig.User or "root";
in
{
  options.nebula = {
    enable = lib.mkEnableOption "Enable Nebula network";
    isLighthouse = lib.mkEnableOption "Is this node a lighthouse?";

    cert = lib.mkOption {
      type = lib.types.path;
      default = "";
      description = "Path to the certificate file";
    };

    key = lib.mkOption {
      type = lib.types.path;
      default = "";
      description = "Path to the key file";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = serviceUser;
      readOnly = true;
      description = "Used to access the user that the nebula service is run as, don't change";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.nebula-ca = {
      format = "binary";
      sopsFile = ./ca.crt.crypt;
      owner = cfg.user;
    };

    environment.systemPackages = with pkgs; [
      nebula
      dig
    ];

    services.nebula.networks."${networkName}" = {
      enable = true;

      inherit (cfg) cert key isLighthouse;
      ca = config.sops.secrets.nebula-ca.path;
      lighthouses = if cfg.isLighthouse then [ ] else [ lighthouseAddress ];

      # run DNS server on the lighthouse
      lighthouse.dns = lib.mkIf cfg.isLighthouse {
        enable = true;
        host = "[::]";
        port = 53;
      };

      listen.port = listenPort;

      staticHostMap = {
        "${lighthouseAddress}" = [ "${machines.ghaf-lighthouse.ip}:${toString listenPort}" ];
      };

      # https://nebula.defined.net/docs/config/punchy
      settings.punchy = {
        punch = true;
        respond = true;
      };

      firewall = {
        outbound = [
          # allow any outbound connections
          {
            port = "any";
            proto = "any";
            host = "any";
          }
        ];
        inbound = [
          # allow ping
          {
            port = "any";
            proto = "icmp";
            host = "any";
          }
          # allow monitoring server to scrape metrics
          {
            port = 9100;
            proto = "tcp";
            groups = [ "scraper" ];
          }
        ]
        ++ (lib.optionals cfg.isLighthouse [
          # allow dns queries to the lighthouse
          {
            port = 53;
            proto = "udp";
            group = "any";
            host = "any";
          }
        ]);
      };
    };

    networking.firewall = {
      # don't stack nixos firewall on top of the nebula firewall
      trustedInterfaces = [ "nebula.${networkName}" ];
      # globally open port 53 to serve DNS
      allowedUDPPorts = lib.mkIf cfg.isLighthouse [ 53 ];
    };
  };
}
