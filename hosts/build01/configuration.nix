# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    inputs.disko.nixosModules.disko
    ../generic-disk-config.nix
    ../common.nix
    ../../services/openssh/openssh.nix
    ../../users/builder.nix
    ../../users/hrosten.nix
  ];
  networking.hostName = "build01";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  boot.loader.grub = {
    devices = ["/dev/sda"];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  # TODO: demo with static IP
  networking.useDHCP = false;
  networking.nameservers = ["192.168.1.1"];
  networking.defaultGateway = "192.168.1.1";
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "192.168.1.107";
      prefixLength = 24;
    }
  ];
}
