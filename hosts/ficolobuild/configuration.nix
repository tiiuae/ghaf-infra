# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  self,
  config,
  inputs,
  lib,
  modulesPath,
  ...
}: {
  imports = lib.flatten [
    (modulesPath + "/installer/scan/not-detected.nix")
    inputs.disko.nixosModules.disko
    (with self.nixosModules; [
      common
      service-openssh
      user-cazfi
      user-hrosten
      user-jrautiola
      user-mkaapu
      user-themisto
    ])
    ./disk-config.nix
  ];

  # Hardwre Configuration:

  boot.initrd.availableKernelModules = ["ahci" "xhci_pci" "megaraid_sas" "nvme" "usbhid" "sd_mod"];
  boot.kernelModules = ["kvm-intel"];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Installation:

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Connect hosts in the same network.
  networking.extraHosts = "
    172.18.20.102 vedenemo.dev # for fetching Gala app sources
    172.18.20.109 cache.vedenemo.dev # Binary cache
  ";

  # Trust Themisto Hydra user
  nix.settings = {
    trusted-users = ["root" "themisto"];
  };
}
