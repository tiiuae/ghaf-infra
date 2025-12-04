# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Profile to import for Azure VMs. Imports azure-common.nix from nixpkgs,
# and configures cloud-init.
{
  config,
  lib,
  ...
}:

let
  cfg = config.virtualisation.azure;
  mlxDrivers = [
    "mlx4_en"
    "mlx4_core"
    "mlx5_core"
  ];
  asGB = size: toString (size * 1024 * 1024 * 1024);
in
{
  options.virtualisation.azure = {
    acceleratedNetworking = lib.mkOption {
      default = false;
      description = "Whether the machine's network interface has enabled accelerated networking.";
    };
  };

  config = {
    nix = {
      settings = {
        # Enable flakes and 'nix' command
        experimental-features = "nix-command flakes";
        # https://github.com/NixOS/nix/issues/11728
        download-buffer-size = 524288000;
        # When free disk space in /nix/store drops below min-free during build,
        # perform a garbage-collection until max-free bytes are available or there
        # is no more garbage.
        min-free = asGB 20;
        max-free = asGB 200;
        # check the free disk space every 5 seconds
        min-free-check-interval = 5;
        # Trust users in the wheel group. They can sudo anyways.
        trusted-users = [ "@wheel" ];
      };
    };
    systemd.services.nix-gc.serviceConfig = {
      Restart = "on-failure";
    };

    services.waagent.enable = true;

    # Enable cloud-init by default for waagent.
    # Otherwise waagent would try manage networking using ifupdown,
    # which is currently not available in nixpkgs.
    services.cloud-init.enable = true;
    services.cloud-init.network.enable = true;
    systemd.services.cloud-config.serviceConfig.Restart = "on-failure";

    # cloud-init.network.enable also enables systemd-networkd
    networking.useDHCP = false;
    networking.useNetworkd = true;

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
    ];

    # EFI configurations for boot
    boot.loader.grub = {
      efiSupport = true;
      efiInstallAsRemovable = true;
    };

    hardware.enableRedistributableFirmware = true;

    # Accelerated networking, configured following:
    # https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-overview
    boot.initrd.availableKernelModules = lib.optionals cfg.acceleratedNetworking mlxDrivers;
    systemd.network.networks."99-azure-unmanaged-devices.network" = lib.mkIf cfg.acceleratedNetworking {
      matchConfig.Driver = mlxDrivers;
      linkConfig.Unmanaged = "yes";
    };
    networking.networkmanager.unmanaged = lib.mkIf cfg.acceleratedNetworking (
      builtins.map (drv: "driver:${drv}") mlxDrivers
    );

    services.udev.extraRules = lib.concatMapStrings (i: ''
      ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:${toString i}", ATTR{removable}=="0", SYMLINK+="disk/by-lun/${toString i}"
    '') (lib.range 1 15);

    security.sudo.enable = true;
    security.sudo.wheelNeedsPassword = false;
  };
}
