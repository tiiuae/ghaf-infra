# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    "${modulesPath}/virtualisation/azure-config.nix"
    self.nixosModules.service-openssh
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # enable cloud-init, so instance metadata is set accordingly and we can use
  # cloud-config for ssh key management.
  services.cloud-init.enable = true;

  # Use systemd-networkd for network configuration, but keep systemd-resolved disabled.
  services.cloud-init.network.enable = true;
  networking.useDHCP = false;
  networking.useNetworkd = true;
  services.resolved.enable = false;

  system.stateVersion = "23.05";
}
