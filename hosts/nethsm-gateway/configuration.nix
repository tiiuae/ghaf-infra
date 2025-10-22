# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  inputs,
  lib,
  config,
  ...
}:
let
  nethsmLogsPort = 514;
  nethsmLogsDestination = "/var/log/nethsm.log";
  nethsmHost = "192.168.70.10";
in
{
  imports =
    [
      ./disk-config.nix
      inputs.sops-nix.nixosModules.sops
      inputs.disko.nixosModules.disko
      ./softhsm.nix
    ]
    ++ (with self.nixosModules; [
      common
      team-devenv
      service-openssh
      service-monitoring
      service-nebula
    ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      loki_password.owner = "promtail";
      nebula-cert.owner = config.nebula.user;
      nebula-key.owner = config.nebula.user;
      nethsm-metrics-credentials.owner = "root";
    };
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "nethsm-gateway";
  networking.useDHCP = true;

  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;
  };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    kernelModules = [ "kvm-intel" ];
    initrd.availableKernelModules = [
      "xhci_pci"
      "thunderbolt"
      "ahci"
      "nvme"
      "uas"
      "usbhid"
      "sd_mod"
    ];
  };

  systemd.services.nethsm-exporter =
    let
      package = self.packages.${pkgs.system}.nethsm-exporter;
      listenPort = 8000;
    in
    {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe package} --hsm-host ${nethsmHost} --port ${toString listenPort}";
        EnvironmentFile = config.sops.secrets.nethsm-metrics-credentials.path;
      };
    };

  services.syslog-ng = {
    enable = true;
    extraConfig = ''
      source s_network_udp { network(ip("0.0.0.0") port(${toString nethsmLogsPort}) transport("udp")); };
      source s_network_tcp { network(ip("0.0.0.0") port(${toString nethsmLogsPort}) transport("tcp")); };

      destination d_nethsm { file("${nethsmLogsDestination}" perm(0644)); };

      log { source(s_network_udp); destination(d_nethsm); };
      log { source(s_network_tcp); destination(d_nethsm); };
    '';
  };

  networking.firewall = {
    allowedUDPPorts = [ nethsmLogsPort ];
    allowedTCPPorts = [ nethsmLogsPort ];
  };

  services.monitoring = {
    metrics.enable = true;
    logs = {
      enable = true;
      lokiAddress = "https://monitoring.vedenemo.dev";
      auth.password_file = config.sops.secrets.loki_password.path;
    };
  };

  services.promtail.configuration.scrape_configs = [
    {
      job_name = "system";
      static_configs = [
        {
          targets = [ "localhost" ];
          labels = {
            job = "nethsm-log";
            host = config.networking.hostName;
            __path__ = nethsmLogsDestination;
          };
        }
      ];
    }
  ];

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
        port = 8000;
        proto = "tcp";
        groups = [ "scraper" ];
      }
      # pkcs11-daemon
      {
        port = 2345;
        proto = "tcp";
        host = "any";
      }
    ];
  };

  # This server is only exposed to the internal network
  # fail2ban only causes issues here
  services.fail2ban.enable = lib.mkForce false;
}
