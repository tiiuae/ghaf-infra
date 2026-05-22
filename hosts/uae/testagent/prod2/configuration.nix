# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  modulesPath,
  lib,
  config,
  ...
}:
{
  imports = [
    ../agents-common.nix
    ./disk-config.nix
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    user-bmg
    user-fayad
    team-devenv
  ]);

  sops.defaultSopsFile = ./secrets.yaml;

  users.groups.tsusers = { };

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

  networking.hostName = "uae-testagent2-prod";
  services.testagent = {
    variant = "prod";
    hardware = [
      "orin-agx"
    ];
  };

  # this server has been installed with 25.11
  system.stateVersion = lib.mkForce "25.11";

  # udev rules for test devices serial connections
  services.udev.extraRules = ''
    # Orin AGX1
    SUBSYSTEM=="tty", KERNEL=="ttyACM[0-9]*", ATTRS{serial}=="TOPO4C3FB81A", ENV{ID_USB_INTERFACE_NUM}=="01", SYMLINK+="ttyAGX1", MODE="0666", GROUP="dialout"
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="50026B7283C099A7", SYMLINK+="ssdORINAGX1", MODE="0666", GROUP="dialout"
  '';

  # Details of the hardware devices connected to this host
  environment.etc."jenkins/test_config.json".text =
    let
      location = config.networking.hostName;
    in
    builtins.toJSON {
      addresses = {
        relay_serial_port = "/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_B0013I2U-if00-port0";
        OrinAGX1 = {
          inherit location;
          device_id = "00-b2-e1-cb-48";
          netvm_hostname = "ghaf-3001142088";
          serial_port = "/dev/ttyAGX1";
          relay_number = 2;
          device_ip_address = "172.20.16.55";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "NONE";
          usbhub_serial = "F997E1F8";
          ext_drive_by-id = "/dev/ssdORINAGX1";
          threads = 12;
        };
      };
    };

}
