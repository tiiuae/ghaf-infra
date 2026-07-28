# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  ...
}:
{
  sops.secrets = lib.mkIf config.services.monitoring.logs.enable {
    loki_password.owner = "alloy";
  };

  services.monitoring.logs = lib.mkIf config.services.monitoring.logs.enable {
    lokiAddress = lib.mkDefault "https://monitoring.vedenemo.dev";
    auth.password_file = config.sops.secrets.loki_password.path;
  };

  networking = {
    useNetworkd = true;
    useDHCP = false;
    usePredictableInterfaceNames = false;
  };

  systemd.network.networks."10-uplink" = {
    matchConfig.Name = "eth0";
    networkConfig.DHCP = "ipv4";
  };

  boot.initrd.availableKernelModules = [
    "ahci" # modern SATA devices
    "sd_mod" # SATA drives
    "nvme" # NVMe drives
    "usbhid" # USB devices
    "xhci_pci" # USB 3.0
  ];
}
