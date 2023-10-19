# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  nixpkgs,
  disko,
}: {
  # NixOS bootstrap config for Azure x86_64 hosts
  # Tested on Azure Gen2 images, with "Standard" security type:
  #  - Ubuntu 22_04-lts-gen2
  #  - Debian 12-gen2
  azure-x86_64-linux = nixpkgs.lib.nixosSystem {
    modules = [
      disko.nixosModules.disko
      ./configuration.nix
      {
        nixpkgs.hostPlatform = nixpkgs.lib.mkDefault "x86_64-linux";
        # Uncomment if you want to enable azure agent (waagent):
        # require = [
        #   "${nixpkgs}/nixos/modules/virtualisation/azure-agent.nix"
        # ];
        # virtualisation.azure.agent.enable = true;
        boot.kernelParams = ["console=ttyS0" "earlyprintk=ttyS0" "rootdelay=300" "panic=1" "boot.panic_on_fail"];
        boot.initrd.kernelModules = ["hv_vmbus" "hv_netvsc" "hv_utils" "hv_storvsc"];
        boot.loader.systemd-boot.enable = true;
        boot.loader.efi.canTouchEfiVariables = true;
        boot.loader.timeout = 0;
        boot.loader.grub.configurationLimit = 0;
        boot.growPartition = true;
        # TODO: make sure the below network and disk configuration match yours:
        disko.devices.disk.disk1.device = "/dev/sda";
        # For instance, to add data disks, you would:
        disko.devices.disk.disk2 = {
          device = "/dev/sdb";
          type = "disk";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/disk2";
          };
        };
        networking.useDHCP = false;
        networking.nameservers = ["8.8.8.8"];
        networking.defaultGateway = "10.3.0.1";
        networking.interfaces.eth0.ipv4.addresses = [
          {
            address = "10.3.0.4";
            prefixLength = 24;
          }
        ];
      }
    ];
  };

  # NixOS bootstrap config for generic x86_64 hosts
  generic-x86_64-linux = nixpkgs.lib.nixosSystem {
    modules = [
      disko.nixosModules.disko
      ./configuration.nix
      {
        nixpkgs.hostPlatform = nixpkgs.lib.mkDefault "x86_64-linux";
        # TODO: make sure the below configuration options match yours:
        disko.devices.disk.disk1.device = "/dev/sda";
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
    ];
  };
}
