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
      ./disk-config.nix
      ../agents-common.nix
      inputs.sops-nix.nixosModules.sops
      inputs.disko.nixosModules.disko
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
      user-vjuntunen
      user-flokli
      user-jrautiola
      user-mariia
      user-leivos
      user-hrosten
      user-ktu
      user-cazfi
      user-fayad
    ]);

  sops.defaultSopsFile = ./secrets.yaml;
  nixpkgs.hostPlatform = "x86_64-linux";

  networking = {
    hostName = "testagent-release";
    useDHCP = true;
  };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    initrd.availableKernelModules = [
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
    kernelModules = [
      "kvm-intel"
      "sg"
    ];
  };

  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;
  };

  # udev rules for test devices serial connections
  services.udev.extraRules = ''
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTCY4MM2", SYMLINK+="ttyORINNX1"
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTCG3MMH", SYMLINK+="ttyNUC1"
    SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea71", ATTRS{serial}=="04A629B8AB8750B711ECB2A4B2B056B", ENV{ID_USB_INTERFACE_NUM}=="01", SYMLINK+="ttyRISCV1", MODE="0666", GROUP="dialout"
  '';

  # Details of the hardware devices connected to this host
  environment.etc."jenkins/test_config.json".text =
    let
      location = config.networking.hostName;
    in
    builtins.toJSON {
      addresses = {
        relay_serial_port = "/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A10KZMAN-if00-port0";
        NUC1 = {
          inherit location;
          serial_port = "/dev/ttyNUC1";
          relay_number = 1;
          device_ip_address = "172.18.16.49";
          socket_ip_address = "172.18.16.53";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usbhub_serial = "6B780E17";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S5T4NJ0NB10775R-0:0";
          threads = 8;
        };
        OrinAGX1 = {
          inherit location;
          serial_port = "/dev/ttyACM0";
          relay_number = 2;
          device_ip_address = "172.18.16.51";
          socket_ip_address = "172.18.16.37";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usbhub_serial = "EBBBCDD4";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6WYNS0W402363J-0:0";
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
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6XNNS0W500889K-0:0";
          threads = 20;
        };
        Polarfire1 = {
          inherit location;
          serial_port = "/dev/ttyRISCV1";
          relay_number = 4;
          device_ip_address = "NONE";
          socket_ip_address = "172.18.16.41";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usb_sd_mux_port = "/dev/usb-sd-mux/id-00048.00197";
          ext_drive_by-id = "usb-LinuxAut_sdFST_HS-SD_MMC_00048.00197-0:0";
          threads = 4;
        };
        OrinNX1 = {
          inherit location;
          serial_port = "/dev/ttyORINNX1";
          relay_number = 3;
          device_ip_address = "172.18.16.46";
          socket_ip_address = "172.18.16.40";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usbhub_serial = "8CC6B0A9";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6WXNS0W300212M-0:0";
          threads = 8;
        };
      };
    };
}
