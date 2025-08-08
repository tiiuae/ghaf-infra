# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  modulesPath,
  self,
  lib,
  machines,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    self.nixosModules.service-monitoring
  ];

  services.monitoring.logs.lokiAddress = lib.mkDefault "http://${machines.ghaf-monitoring.internal_ip}:3100";

  hardware.enableRedistributableFirmware = true;
  networking.useDHCP = true;

  # disable firewall on hetzner internal network
  networking.firewall.trustedInterfaces = [ "eth1" ];

  boot = {
    # disable predictable NIC names as they vary between hetzner servers
    # this forces the creation of standard names like eth0 and eth1
    kernelParams = [ "net.ifnames=0" ];

    # grub boot loader with EFI
    loader.grub = {
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
  };
}
