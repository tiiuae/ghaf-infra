# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.virtualisation.azure;
in
{
  options = {
    virtualisation.azure = {
      acceleratedNetworking = lib.mkOption {
        default = false;
        description = "Whether the machine's network interface has enabled accelerated networking.";
      };
    };
  };

  config = lib.mkMerge [
    {
      services.waagent.enable = true;

      # Enable cloud-init by default for waagent.
      # Otherwise waagent would try manage networking using ifupdown,
      # which is currently not available in nixpkgs.
      services.cloud-init = {
        enable = true;
        network.enable = true;
      };
      systemd.services.cloud-config.serviceConfig.Restart = "on-failure";

      # cloud-init.network.enable also enables systemd-networkd
      networking = {
        useDHCP = false;
        useNetworkd = true;
      };

      # Ensure kernel outputs to ttyS0 (Azure Serial Console),
      # and reboot machine upon fatal boot issues
      boot.kernelParams = [
        "console=ttyS0"
        "earlyprintk=ttyS0"
        "rootdelay=300"
        "panic=1"
        "boot.panic_on_fail"
        "net.ifnames=0"
      ];

      # Load Hyper-V kernel modules
      boot.initrd.kernelModules = [
        "hv_vmbus"
        "hv_netvsc"
        "hv_utils"
        "hv_storvsc"
        "virtio_gpu"
      ];

      services.udev.extraRules = lib.concatMapStrings (i: ''
        ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:${toString i}", ATTR{removable}=="0", SYMLINK+="disk/by-lun/${toString i}"
      '') (lib.range 1 15);
    }
    (lib.mkIf cfg.acceleratedNetworking (
      let
        mlxDrivers = [
          "mlx4_en"
          "mlx4_core"
          "mlx5_core"
        ];
      in
      {
        # Accelerated networking, configured following:
        # https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-overview
        boot.initrd.availableKernelModules = mlxDrivers;
        systemd.network.networks."99-azure-unmanaged-devices.network" = {
          matchConfig.Driver = mlxDrivers;
          linkConfig.Unmanaged = "yes";
        };
        networking.networkmanager.unmanaged = map (drv: "driver:${drv}") mlxDrivers;
      }
    ))
  ];
}
