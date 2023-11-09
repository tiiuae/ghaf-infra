# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{inputs, ...}: {
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

  # Ref:
  # - https://github.com/NixOS/nixpkgs/blob/8efd5d1e283604f75a808a20e6cde0ef313d07d4/nixos/modules/virtualisation/azure-common.nix#L44
  # - https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/troubleshoot-device-names-problems
  services.udev.extraRules = ''
    ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:0", ATTR{removable}=="0", SYMLINK+="disk/by-lun/0",
    ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:1", ATTR{removable}=="0", SYMLINK+="disk/by-lun/1",
    ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:2", ATTR{removable}=="0", SYMLINK+="disk/by-lun/2"
    ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:3", ATTR{removable}=="0", SYMLINK+="disk/by-lun/3"

    ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:4", ATTR{removable}=="0", SYMLINK+="disk/by-lun/4"
    ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:5", ATTR{removable}=="0", SYMLINK+="disk/by-lun/5"
    ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:6", ATTR{removable}=="0", SYMLINK+="disk/by-lun/6"
    ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:7", ATTR{removable}=="0", SYMLINK+="disk/by-lun/7"

    ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:8", ATTR{removable}=="0", SYMLINK+="disk/by-lun/8"
    ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:9", ATTR{removable}=="0", SYMLINK+="disk/by-lun/9"
    ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:10", ATTR{removable}=="0", SYMLINK+="disk/by-lun/10"
    ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:11", ATTR{removable}=="0", SYMLINK+="disk/by-lun/11"

    ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:12", ATTR{removable}=="0", SYMLINK+="disk/by-lun/12"
    ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:13", ATTR{removable}=="0", SYMLINK+="disk/by-lun/13"
    ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:14", ATTR{removable}=="0", SYMLINK+="disk/by-lun/14"
    ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:15", ATTR{removable}=="0", SYMLINK+="disk/by-lun/15"
  '';
}
