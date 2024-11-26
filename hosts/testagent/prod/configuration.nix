# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  self,
  inputs,
  config,
  ...
}:
{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../agents-common.nix
    ]
    ++ (with inputs; [
      sops-nix.nixosModules.sops
      disko.nixosModules.disko
    ])
    ++ (with self.nixosModules; [
      common
      service-openssh
      user-vjuntunen
      user-flokli
      user-jrautiola
      user-mariia
      user-maarit
      user-leivos
      user-hrosten
    ]);

  networking = {
    hostName = "testagent-prod";
    useNetworkd = true;
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # udev rules for test devices serial connections
  services.udev.extraRules = ''
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTD1BQQS", SYMLINK+="ttyORINNX1", MODE="0666", GROUP="dialout"
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTC0VRXR", SYMLINK+="ttyNUC1", MODE="0666", GROUP="dialout"
    SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea71", ATTRS{serial}=="0642246B630C149011EC987B167DB04", ENV{ID_USB_INTERFACE_NUM}=="01", SYMLINK+="ttyRISCV1", MODE="0666", GROUP="dialout"
  '';

  # Details of the hardware devices connected to this host
  environment.etc."jenkins/test_config.json".text =
    let
      location = config.networking.hostName;
    in
    builtins.toJSON {
      addresses = {
        NUC1 = {
          inherit location;
          serial_port = "/dev/ttyNUC1";
          device_ip_address = "172.18.16.50";
          socket_ip_address = "172.18.16.30";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usbhub_serial = "F0A0D6CF";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6XPNJ0TB00828W-0:0";
          threads = 8;
        };
        OrinAGX1 = {
          inherit location;
          serial_port = "/dev/ttyACM0";
          device_ip_address = "172.18.16.36";
          socket_ip_address = "172.18.16.31";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usbhub_serial = "92D8AEB7";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6WXNS0W300153T-0:0";
          threads = 8;
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
        Polarfire1 = {
          inherit location;
          serial_port = "/dev/ttyRISCV1";
          device_ip_address = "NONE";
          socket_ip_address = "172.18.16.45";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usb_sd_mux_port = "/dev/sg1";
          ext_drive_by-id = "usb-LinuxAut_sdmux_HS-SD_MMC_000000001184-0:0";
          threads = 4;
        };
        OrinNX1 = {
          inherit location;
          serial_port = "/dev/ttyORINNX1";
          device_ip_address = "172.18.16.44";
          socket_ip_address = "172.18.16.43";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usbhub_serial = "5220564F";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6XPNS0T918984B-0:0";
          threads = 8;
        };
      };
    };
}
