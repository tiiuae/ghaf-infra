# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  ...
}: {
  imports = lib.flatten [
    [
      inputs.disko.nixosModules.disko
    ]
    (with self.nixosModules; [
      common
      azure-common
      generic-disk-config
      service-openssh
      user-bmg
      user-builder
      user-hrosten
    ])
  ];
  networking.hostName = "build01";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  boot.loader.grub = {
    devices = ["/dev/sda"];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  # TODO: demo with static IP:
  networking.useDHCP = false;
  networking.nameservers = ["1.1.1.1" "8.8.8.8"];
  networking.defaultGateway = "10.3.0.1";
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.3.0.5";
      prefixLength = 24;
    }
  ];
}
