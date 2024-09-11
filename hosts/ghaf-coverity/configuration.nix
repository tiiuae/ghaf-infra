# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  modulesPath,
  lib,
  ...
}:
{
  sops.defaultSopsFile = ./secrets.yaml;

  imports =
    [
      ./disk-config.nix
      (modulesPath + "/profiles/qemu-guest.nix")
      inputs.sops-nix.nixosModules.sops
      inputs.disko.nixosModules.disko
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
      user-jrautiola
      user-ktu
    ]);

  # this server has been installed with 24.05
  system.stateVersion = lib.mkForce "24.05";

  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "ghaf-coverity";
    useDHCP = true;
  };

  boot = {
    # use predictable network interface names (eth0)
    kernelParams = [ "net.ifnames=0" ];
    loader.grub = {
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
  };
}
