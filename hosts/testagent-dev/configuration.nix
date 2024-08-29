# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  pkgs,
  ...
}:
let
  # Vendored in, as brainstem isn't suitable for nixpkgs packaging upstream:
  # https://github.com/NixOS/nixpkgs/pull/313643
  brainstem = pkgs.callPackage ../../pkgs/brainstem { };
in
{
  imports =
    [
      ./disk-config.nix
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

  services.udev = {
    # Enable Acroname USB Smart switch, as well as LXA USB-SD-Mux support.
    packages = [
      brainstem
      pkgs.usbsdmux
    ];

    # udev rules for test devices serial connections
    extraRules = ''
      SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTD1BQQS", SYMLINK+="ttyORINNX1", MODE="0666", GROUP="dialout"
      SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea71", ATTRS{serial}=="0642246B630C149011EC987B167DB04", ENV{ID_USB_INTERFACE_NUM}=="01", SYMLINK+="ttyRISCV1", MODE="0666", GROUP="dialout"
    '';
  };

  environment.systemPackages =
    [
      inputs.robot-framework.packages.${pkgs.system}.ghaf-robot
      brainstem
    ]
    ++ (with pkgs; [
      minicom
      usbsdmux
    ]);

  # Details of the hardware devices connected to this host
  environment.etc."jenkins/test_config.json".text = builtins.toJSON { addresses = { }; };
}
