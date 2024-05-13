# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  ...
}: {
  sops.defaultSopsFile = ./secrets.yaml;

  imports =
    [
      ./disk-config.nix
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
      service-node-exporter
      user-jrautiola
    ]);

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "hetzarm";
    useDHCP = true;
  };

  boot = {
    initrd.availableKernelModules = ["nvme" "usbhid"];
    # use predictable network interface names (eth0)
    kernelParams = ["net.ifnames=0"];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };
}
