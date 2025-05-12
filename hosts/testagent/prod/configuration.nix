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
      ./hardware-configuration.nix
    ]
    ++ (with self.nixosModules; [
      team-devenv
      team-testers
      user-flokli
    ]);

  sops.defaultSopsFile = ./secrets.yaml;
  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "testagent-prod";
  services.testagent = {
    variant = "prod";
    hardware = [
      "orin-agx"
      "orin-nx"
      "orin-agx-64"
      "lenovo-x1"
      "dell-7330"
    ];
  };

  # udev rules for test devices serial connections
  services.udev.extraRules = ''
    # Orin nx
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTD0W9KS", SYMLINK+="ttyORINNX1", MODE="0666", GROUP="dialout"

    # Orin AGX1
    SUBSYSTEM=="tty", KERNEL=="ttyACM[0-9]*", ATTRS{serial}=="TOPO375FF8FA", ENV{ID_USB_INTERFACE_NUM}=="01", SYMLINK+="ttyAGX1", MODE="0666", GROUP="dialout"

    # Orin AGX64
    SUBSYSTEM=="tty", KERNEL=="ttyACM[0-9]*", ATTRS{serial}=="TOPO47B579E5", ENV{ID_USB_INTERFACE_NUM}=="01", SYMLINK+="ttyAGX64", MODE="0666", GROUP="dialout"
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
          serial_port = "/dev/ttyAGX64";
          relay_number = 3;
          device_ip_address = "172.18.16.50";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "NONE";
          usbhub_serial = "F0A0D6CF";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6XPNJ0TB00828W-0:0";
          threads = 12;
        };
        OrinAGX1 = {
          inherit location;
          serial_port = "/dev/ttyAGX1";
          relay_number = 4;
          device_ip_address = "172.18.16.36";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "NONE";
          usbhub_serial = "92D8AEB7";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6WXNS0W300153T-0:0";
          threads = 12;
        };
        LenovoX1-1 = {
          inherit location;
          serial_port = "NONE";
          device_ip_address = "172.18.16.66";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "LenovoX1-prod";
          usbhub_serial = "641B6D74";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S7MLNS0X532696T-0:0";
          threads = 20;
        };
        OrinNX1 = {
          inherit location;
          serial_port = "/dev/ttyORINNX1";
          relay_number = 2;
          device_ip_address = "172.18.16.44";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "NONE";
          usbhub_serial = "5220564F";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6XPNS0T918984B-0:0";
          threads = 8;
        };
        Dell7330 = {
          inherit location;
          serial_port = "NONE";
          device_ip_address = "172.18.16.7";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "Dell7330-prod";
          usbhub_serial = "FF62140D";
          ext_drive_by-id = "usb-Kingston_XS2000_50026B72836E78E0-0:0";
          threads = 8;
        };
        measurement_agent = {
          inherit location;
          device_ip_address = "172.18.16.10";
        };
      };
    };
}
