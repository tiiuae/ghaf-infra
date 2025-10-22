# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  modulesPath,
  self,
  lib,
  machines,
  config,
  ...
}:
let
  defaultLoki = "http://${machines.ghaf-monitoring.internal_ip}:3100";
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    self.nixosModules.service-monitoring
  ];

  services.monitoring.logs.lokiAddress = lib.mkDefault defaultLoki;

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

  warnings = [
    (lib.mkIf
      (
        (config.services.monitoring.logs.lokiAddress == defaultLoki)
        # naively assume name in machines matches hostname for now
        && (!builtins.hasAttr "internal_ip" machines.${config.networking.hostName})
      )
      "${config.networking.hostName} sends logs to hetzner internal network but has no internal ip defined! is it part of the network?"
    )
  ];
}
