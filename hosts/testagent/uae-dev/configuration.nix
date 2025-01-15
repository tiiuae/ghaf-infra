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
      user-fayad
    ]);

  sops.defaultSopsFile = ./secrets.yaml;
  nixpkgs.hostPlatform = "x86_64-linux";

  networking = {
    hostName = "testagent-uae-dev";
    useDHCP = true;
  };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    initrd.availableKernelModules = [
      "xhci_pci"
      "nvme"
      "thunderbolt"
    ];
    kernelModules = [
      "kvm-intel"
    ];
  };

  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;
  };

  # udev rules for test devices serial connections
  # placeholder configs from finland. need updation with new uae targets, in progress
  services.udev.extraRules = ''
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTD0W9KS", SYMLINK+="ttyORINNX1", MODE="0666", GROUP="dialout"
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTD0WF8Y", SYMLINK+="ttyNUC1", MODE="0666", GROUP="dialout"
    SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea71", ATTRS{serial}=="04A629B8AB87AB8111ECB2A38815028", ENV{ID_USB_INTERFACE_NUM}=="01", SYMLINK+="ttyRISCV1", MODE="0666", GROUP="dialout"
  '';

  # Details of the hardware devices connected to this host
  # placeholder configs from finland. configs in progress based on new uae targets
  environment.etc."jenkins/test_config.json".text =
    let
      location = config.networking.hostName;
    in
    builtins.toJSON {
      addresses = {
        OrinAGX1 = {
          inherit location;
          serial_port = "/dev/ttyACM0";
          device_ip_address = "172.19.16.13";
          socket_ip_address = "172.19.16.23";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usbhub_serial = "0x2954223B";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6XNNS0W202677W-0:0";
          threads = 8;
        };
        LenovoX1-1 = {
          inherit location;
          serial_port = "NONE";
          device_ip_address = "172.19.16.14";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "LenovoX1-uae-dev";
          usbhub_serial = "0x99EB9D84";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6XPNS0W606188E-0:0";
          threads = 20;
        };
      };
    };
}
