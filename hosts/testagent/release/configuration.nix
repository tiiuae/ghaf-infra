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
  networking.hostName = "testagent-release";
  services.testagent = {
    variant = "release";
    hardware = [
      "orin-agx"
      "orin-nx"
      "lenovo-x1"
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

  # udev rules for test devices serial connections
  services.udev.extraRules = ''
    # Orin nx
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTCY4MM2", SYMLINK+="ttyORINNX1"
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S6WXNS0W300212M", SYMLINK+="ssdORINNX1", MODE="0666", GROUP="dialout"

    # Orin agx
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S6WYNS0W402363J", SYMLINK+="ssdORINAGX1", MODE="0666", GROUP="dialout"

    # Lenovo X1
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S6XNNS0W500889K", SYMLINK+="ssdX1", MODE="0666", GROUP="dialout"
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
        relay_serial_port = "/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A10KZMAN-if00-port0";
        OrinAGX1 = {
          inherit location;
          serial_port = "/dev/ttyACM0";
          relay_number = 2;
          device_ip_address = "172.18.16.51";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "NONE";
          usbhub_serial = "EBBBCDD4";
          ext_drive_by-id = "/dev/ssdORINAGX1";
          threads = 12;
        };
        LenovoX1-1 = {
          inherit location;
          serial_port = "NONE";
          device_ip_address = "172.18.16.64";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "LenovoX1-release";
          usbhub_serial = "5F166079";
          ext_drive_by-id = "/dev/ssdX1";
          threads = 20;
        };
        OrinNX1 = {
          inherit location;
          serial_port = "/dev/ttyORINNX1";
          relay_number = 3;
          device_ip_address = "172.18.16.46";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "NONE";
          usbhub_serial = "8CC6B0A9";
          ext_drive_by-id = "/dev/ssdORINNX1";
          threads = 8;
        };
      };
    };
}
