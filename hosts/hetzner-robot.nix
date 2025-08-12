# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  inputs,
  config,
  ...
}:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    self.nixosModules.service-monitoring
  ];

  sops.secrets = lib.mkIf config.services.monitoring.logs.enable {
    loki_password.owner = "promtail";
  };

  services.monitoring.logs = lib.mkIf config.services.monitoring.logs.enable {
    lokiAddress = lib.mkDefault "https://monitoring.vedenemo.dev";
    auth.password_file = config.sops.secrets.loki_password.path;
  };

  hardware.enableRedistributableFirmware = true;
  networking.useDHCP = true;

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  boot.initrd.availableKernelModules = [
    "ahci" # modern SATA devices
    "nvme" # NVMe drives
    "usbhid" # USB devices
    "xhci_pci" # USB 3.0
  ];
}
