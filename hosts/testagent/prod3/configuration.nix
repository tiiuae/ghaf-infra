# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ self, inputs, ... }:
{
  imports = [
    ./disk-config.nix
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    openssh
    team-devenv
    team-testers
  ]);

  # Initial installation without agent services or runtime secrets.
  sops.defaultSopsFile = ./secrets.yaml;

  boot = {
    kernelModules = [ "kvm-intel" ];
    initrd.availableKernelModules = [
      "xhci_pci"
      "ahci"
      "usbhid"
      "usb_storage"
      "sd_mod"
      "rtsx_pci_sdmmc"
    ];
    loader.efi.canTouchEfiVariables = true;
  };

  system.stateVersion = "26.11";
  networking.hostName = "testagent3-prod";
  networking.useDHCP = true;
  hardware.cpu.intel.updateMicrocode = true;
}
