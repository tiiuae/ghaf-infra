# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  config,
  ...
}:
{
  imports = [
    ../agents-common.nix
    ./disk-config.nix
  ];

  sops.defaultSopsFile = ./secrets.yaml;

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
          device_id = "00-fc-3a-cf-35";
          netvm_hostname = "ghaf-4231712565";
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
          device_id = "00-20-fd-ee-9c";
          netvm_hostname = "ghaf-0553512604";
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
          device_id = "00-0b-73-3f-1e";
          netvm_hostname = "ghaf-0192102174";
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
