# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  config,
  pkgs,
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
      user-tervis
      user-karim
      user-mika
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

  # Environment for Yubikey provisioning
  environment.systemPackages = with pkgs; [
    usbutils
    screen
    python310
  ];
  virtualisation.docker.enable = true;
}
