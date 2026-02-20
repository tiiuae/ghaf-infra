# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  config,
  #  machines,
  pkgs,
  ...
}:
{
  imports = [
    ./disk-config.nix
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
    ../../nethsm-gateway/nethsm.nix
  ]
  ++ (with self.nixosModules; [
    common
    team-devenv
    user-bmg
    user-ctsopokis
    service-openssh
    #    service-nebula
    service-monitoring
  ]);

  environment.systemPackages = with pkgs; [
    inetutils
    net-tools
  ];

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      loki_password.owner = "alloy";
      #      nebula-cert.owner = config.nebula.user;
      #      nebula-key.owner = config.nebula.user;
    };
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "uae-nethsm-gateway";

  # Assign IP configs because dhcp is disabled in network
  networking = {
    useDHCP = true;
    interfaces.enp3s0 = {
      ipv4.addresses = [
        {
          address = "172.31.141.51";
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
      "usbhid"
      "usb_storage"
      "sd_mod"
    ];
  };

  nethsm.host = "192.168.70.20";
  pkcs11.proxy.listenAddr = "0.0.0.0";

  services.monitoring = {
    metrics.enable = true;
    logs = {
      enable = true;
      lokiAddress = "https://monitoring.vedenemo.dev";
      auth.password_file = config.sops.secrets.loki_password.path;
    };

    alloy.configFiles.nethsm = # hcl
      ''
        local.file_match "nethsm" {
        	path_targets = [{
        		__address__ = "localhost",
        		__path__    = "${config.nethsm.logging.file}",
        		host        = "${config.networking.hostName}",
        		job         = "nethsm-log",
        	}]
        }

        loki.source.file "nethsm" {
        	targets               = local.file_match.nethsm.targets
        	forward_to            = [loki.write.default.receiver]
        }
      '';
  };

  #  nebula = {
  #    enable = true;
  #    cert = config.sops.secrets.nebula-cert.path;
  #    key = config.sops.secrets.nebula-key.path;
  #  };
  #
  #  services.nebula.networks."vedenemo".firewall = {
  #    outbound = lib.mkForce [
  #      # allow udp outbound only to hetzner, uae-lab
  #      {
  #        port = 4242;
  #        proto = "udp";
  #        groups = [
  #          "hetzner"
  #          "uae-lab"
  #          "uae-azureci"
  #        ];
  #      }
  #      # allow dns requests
  #      {
  #        port = 53;
  #        proto = "udp";
  #        host = "any";
  #      }
  #      # allow any tcp or icmp outbound (between nebula hosts)
  #      {
  #        port = "any";
  #        proto = "tcp";
  #        host = "any";
  #      }
  #      {
  #        port = "any";
  #        proto = "icmp";
  #        host = "any";
  #      }
  #    ];
  #    inbound = [
  #      # allow monitoring server to scrape nethsm metrics
  #      {
  #        inherit (config.nethsm.exporter) port;
  #        proto = "tcp";
  #        groups = [ "scraper" ];
  #      }
  #      # allow hetzner and uae-lab servers to connect
  #      {
  #        port = 22;
  #        proto = "tcp";
  #        groups = [
  #          "hetzner"
  #          "uae-lab"
  #          "uae-azureci"
  #        ];
  #      }
  #      # pkcs11-daemon
  #      {
  #        port = config.pkcs11.proxy.listenPort;
  #        proto = "tcp";
  #        host = "any";
  #      }
  #    ];
  #  };
  #
  # This server is only exposed to the internal network
  # fail2ban only causes issues here
  services.fail2ban.enable = lib.mkForce false;
}
