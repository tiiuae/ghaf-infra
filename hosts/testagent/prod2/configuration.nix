# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  self,
  config,
  ...
}:
{
  imports = [
    ../agents-common.nix
    ./disk-config.nix
  ]
  ++ (with self.nixosModules; [
    service-nebula
    team-devenv
    team-testers
  ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      metrics_password.owner = "alloy";
      nebula-cert.owner = config.nebula.user;
      nebula-key.owner = config.nebula.user;
    };
  };

  boot = {
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

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "testagent2-prod";
  services.testagent = {
    variant = "prod";
    hardware = [
      "orin-agx"
      "orin-nx"
      "orin-agx-64"
    ];
  };

  nebula = {
    enable = true;
    cert = config.sops.secrets.nebula-cert.path;
    key = config.sops.secrets.nebula-key.path;
  };

  services.nebula.networks."vedenemo".firewall = {
    inbound = [
      {
        port = 8000;
        proto = "tcp";
        groups = [ "scraper" ];
      }
    ];
  };

  # udev rules for test devices serial connections
  services.udev.extraRules = ''
    # Orin nx
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTD0W9KS", SYMLINK+="ttyORINNX1", MODE="0666", GROUP="dialout"
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S6XPNS0T918984B", SYMLINK+="ssdORINNX1", MODE="0666", GROUP="dialout"

    # Orin AGX1
    SUBSYSTEM=="tty", KERNEL=="ttyACM[0-9]*", ATTRS{serial}=="TOPO375FF8FA", ENV{ID_USB_INTERFACE_NUM}=="01", SYMLINK+="ttyAGX1", MODE="0666", GROUP="dialout"
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S7MENS0X421860P", SYMLINK+="ssdORINAGX1", MODE="0666", GROUP="dialout"

    # Orin AGX64
    SUBSYSTEM=="tty", KERNEL=="ttyACM[0-9]*", ATTRS{serial}=="TOPO47B579E5", ENV{ID_USB_INTERFACE_NUM}=="01", SYMLINK+="ttyAGX64", MODE="0666", GROUP="dialout"
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S6XPNJ0TB00828W", SYMLINK+="ssdORINAGX64", MODE="0666", GROUP="dialout"

  '';

  # Trigger UDEV rules
  system.activationScripts.udevTrigger = ''
    echo "==> Triggering udev rules..."
    /run/current-system/sw/bin/udevadm trigger --subsystem-match=tty
    /run/current-system/sw/bin/udevadm trigger --subsystem-match=block
  '';

  # Details of the hardware devices connected to this host
  environment.etc."jenkins/test_config.json".text =
    let
      location = config.networking.hostName;
    in
    builtins.toJSON {
      addresses = {
        relay_serial_port = "/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A10KZ5VO-if00-port0";
        OrinAGX64 = {
          inherit location;
          device_id = "00-32-12-3f-43";
          netvm_hostname = "ghaf-0840056643";
          serial_port = "/dev/ttyAGX64";
          relay_number = 3;
          device_ip_address = "172.18.16.50";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "NONE";
          usbhub_serial = "F0A0D6CF";
          ext_drive_by-id = "/dev/ssdORINAGX64";
          threads = 12;
        };
        OrinAGX1 = {
          inherit location;
          device_id = "00-27-68-e6-94";
          netvm_hostname = "ghaf-0661186196";
          serial_port = "/dev/ttyAGX1";
          relay_number = 4;
          device_ip_address = "172.18.16.36";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "NONE";
          usbhub_serial = "FD70061F";
          ext_drive_by-id = "/dev/ssdORINAGX1";
          threads = 12;
        };
        OrinNX1 = {
          inherit location;
          device_id = "00-5a-2f-8c-44";
          netvm_hostname = "ghaf-1513065540";
          serial_port = "/dev/ttyORINNX1";
          relay_number = 2;
          device_ip_address = "172.18.16.44";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "NONE";
          usbhub_serial = "5220564F";
          ext_drive_by-id = "/dev/ssdORINNX1";
          threads = 8;
        };
      };
    };
}
