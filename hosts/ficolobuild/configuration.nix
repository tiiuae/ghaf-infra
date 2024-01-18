# SPDX-FileCopyrightText: 2023-2024 Technology Innovation Institute (TII)
# SPDX-License-Identifier: Apache-2.0
#
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
      ficolo-common
      service-openssh
      service-node-exporter
      user-cazfi
      user-hrosten
      user-jrautiola
      user-mkaapu
      user-themisto
      user-tervis
      user-karim
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

  # Trust Themisto Hydra user
  nix.settings = {
    trusted-users = ["root" "themisto"];
  };
}
