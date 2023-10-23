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
  # TODO: demo with static IP:
  networking.useDHCP = false;
  networking.nameservers = ["8.8.8.8"];
  networking.defaultGateway = "10.3.0.1";
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.3.0.5";
      prefixLength = 24;
    }
  ];
  # TODO: below options are required to demo this configuration on azure VM:
  require = [
    "${inputs.nixpkgs}/nixos/modules/virtualisation/azure-agent.nix"
  ];
  virtualisation.azure.agent.enable = true;
  boot.kernelParams = ["console=ttyS0" "earlyprintk=ttyS0" "rootdelay=300" "panic=1" "boot.panic_on_fail"];
  boot.initrd.kernelModules = ["hv_vmbus" "hv_netvsc" "hv_utils" "hv_storvsc"];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 0;
  boot.loader.grub.configurationLimit = 0;
  boot.growPartition = true;
}
