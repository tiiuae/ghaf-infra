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
      user-maarit
      user-leivos
      user-hrosten
    ]);

  sops.defaultSopsFile = ./secrets.yaml;
  nixpkgs.hostPlatform = "x86_64-linux";

  networking = {
    hostName = "testagent-dev";
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
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTD0W9KS", SYMLINK+="ttyORINNX1", MODE="0666", GROUP="dialout"
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTD0WF8Y", SYMLINK+="ttyNUC1", MODE="0666", GROUP="dialout"
    SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea71", ATTRS{serial}=="04A629B8AB87AB8111ECB2A38815028", ENV{ID_USB_INTERFACE_NUM}=="01", SYMLINK+="ttyRISCV1", MODE="0666", GROUP="dialout"
  '';

  # Details of the hardware devices connected to this host
  environment.etc."jenkins/test_config.json".text =
    let
      location = config.networking.hostName;
    in
    builtins.toJSON {
      addresses = {
        OrinAGX1 = {
          inherit location;
          serial_port = "/dev/ttyACM0";
          device_ip_address = "172.18.16.54";
          socket_ip_address = "172.18.16.74";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usbhub_serial = "0x2954223B";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6XNNS0W202677W-0:0";
          threads = 8;
        };
        OrinNX1 = {
          inherit location;
          serial_port = "/dev/ttyORINNX1";
          device_ip_address = "172.18.16.61";
          socket_ip_address = "172.18.16.95";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usbhub_serial = "0xEE92E4FD";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6XPNS0W606359P-0:0";
          threads = 8;
        };
        Polarfire1 = {
          inherit location;
          serial_port = "/dev/ttyRISCV1";
          device_ip_address = "NONE";
          socket_ip_address = "172.18.16.82";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usb_sd_mux_port = "/dev/usb-sd-mux/id-000000001488";
          ext_drive_by-id = "usb-LinuxAut_sdmux_HS-SD_MMC_000000001488-0:0";
          threads = 4;
        };
        NUC1 = {
          inherit location;
          serial_port = "/dev/ttyNUC1";
          device_ip_address = "172.18.16.16";
          socket_ip_address = "172.18.16.20";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usbhub_serial = "0x029CEAF3";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6XNNS0W201129V-0:0";
          threads = 8;
        };
        LenovoX1-1 = {
          inherit location;
          serial_port = "NONE";
          device_ip_address = "172.18.16.17";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "LenovoX1-dev";
          usbhub_serial = "0x99EB9D84";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6XPNS0W606188E-0:0";
          threads = 20;
        };
      };
    };
}
