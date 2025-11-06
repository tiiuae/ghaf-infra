# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  ...
}:
{
  imports = [
    ./disk-config.nix
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    team-devenv
    service-openssh
  ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "uae-nethsm-gateway";

  # Assign IP configs because dhcp is disabled in network
  networking = {
    useDHCP = true;
    interfaces.enp3s0 = {
      ipv4.addresses = [
        {
          address = "172.31.141.51";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "172.31.141.1";
      interface = "enp3s0";
    };
    nameservers = [
      "10.161.10.11"
      "10.161.10.12"
    ];
  };

  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;
  };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    kernelModules = [ "kvm-intel" ];
    initrd.availableKernelModules = [
      "xhci_pci"
      "thunderbolt"
      "ahci"
      "nvme"
      "usbhid"
      "usb_storage"
      "sd_mod"
    ];
  };
  # This server is only exposed to the internal network
  # fail2ban only causes issues here
  services.fail2ban.enable = lib.mkForce false;
}
