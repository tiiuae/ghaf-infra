# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  config,
  ...
}:
{
  imports =
    [
      ../agents-common.nix
      ./disk-config.nix
    ]
    ++ (with self.nixosModules; [
      team-devenv
      team-testers
      user-flokli
    ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets.metrics_password.owner = "root";
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "testagent-dev";
  services.testagent = {
    variant = "dev";
    hardware = [
      "orin-agx"
      "orin-nx"
      "orin-agx-64"
      "lenovo-x1"
      "dell-7330"
    ];
  };

  boot.initrd.availableKernelModules = [
    "vmd"
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "sr_mod"
    "rtsx_pci_sdmmc"
  ];
  boot.kernelModules = [
    "kvm-intel"
    "sg"
  ];

  # udev rules for test devices serial connections and SSD-drives
  services.udev.extraRules = ''
    # Orin nx
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTD1BQQS", SYMLINK+="ttyORINNX1", MODE="0666", GROUP="dialout"
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S6XPNS0W606359P", SYMLINK+="ssdORINNX1", MODE="0666", GROUP="dialout"

    # Orin AGX1
    SUBSYSTEM=="tty", KERNEL=="ttyACM[0-9]*", ATTRS{serial}=="TOPOC39C0EE1", ENV{ID_USB_INTERFACE_NUM}=="01", SYMLINK+="ttyAGX1", MODE="0666", GROUP="dialout"
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S6XNNS0W202677W", SYMLINK+="ssdORINAGX1", MODE="0666", GROUP="dialout"

    # Orin AGX64
    SUBSYSTEM=="tty", KERNEL=="ttyACM[0-9]*", ATTRS{serial}=="TOPOB63758F2", ENV{ID_USB_INTERFACE_NUM}=="01", SYMLINK+="ttyAGX64", MODE="0666", GROUP="dialout"
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S6XNNS0W201129V", SYMLINK+="ssdORINAGX64", MODE="0666", GROUP="dialout"

    # Lenovo X1
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S6XPNS0W606188E", SYMLINK+="ssdX1", MODE="0666", GROUP="dialout"

    # Dell 7330
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S6XNNS0W500904J", SYMLINK+="ssdDELL7330", MODE="0666", GROUP="dialout"
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
        relay_serial_port = "/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A10KYI3B-if00-port0";
        OrinAGX1 = {
          inherit location;
          serial_port = "/dev/ttyAGX1";
          relay_number = 4;
          device_ip_address = "172.18.16.54";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "NONE";
          usbhub_serial = "0x2954223B";
          ext_drive_by-id = "/dev/ssdORINAGX1";
          threads = 12;
        };
        OrinNX1 = {
          inherit location;
          serial_port = "/dev/ttyORINNX1";
          relay_number = 3;
          device_ip_address = "172.18.16.61";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "NONE";
          usbhub_serial = "0xEE92E4FD";
          ext_drive_by-id = "/dev/ssdORINNX1";
          threads = 8;
        };
        OrinAGX64 = {
          inherit location;
          relay_number = 1;
          serial_port = "/dev/ttyAGX64";
          device_ip_address = "172.18.16.16";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "NONE";
          usbhub_serial = "0x029CEAF3";
          ext_drive_by-id = "/dev/ssdORINAGX64";
          threads = 12;
        };
        LenovoX1-1 = {
          inherit location;
          serial_port = "NONE";
          device_ip_address = "172.18.16.17";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "LenovoX1-dev";
          usbhub_serial = "0x99EB9D84";
          ext_drive_by-id = "/dev/ssdX1";
          threads = 20;
        };
        Dell7330 = {
          inherit location;
          serial_port = "NONE";
          device_ip_address = "172.18.16.23";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "Dell7330-dev";
          usbhub_serial = "5AC2B4AD";
          ext_drive_by-id = "/dev/ssdDELL7330";
          threads = 8;
        };
      };
    };
}
