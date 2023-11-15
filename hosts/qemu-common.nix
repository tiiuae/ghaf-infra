# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  services.qemuGuest.enable = true;

  boot = {
    kernelParams = ["console=ttyS0" "earlyprintk=ttyS0" "rootdelay=300" "panic=1" "boot.panic_on_fail"];
    initrd = {
      availableKernelModules = ["ahci" "xhci_pci" "virtio_pci" "sr_mod" "virtio_blk" "uhci_hcd" "ehci_pci" "virtio_scsi"];
      kernelModules = ["kvm-intel" "dm-snapshot"];
    };

    loader.grub = {
      enable = true;
      # qemu vms are using SeaBIOS which is not UEFI
      efiSupport = false;
    };
  };

  networking.extraHosts = ''
    172.18.20.109 cache.vedenemo.dev
  '';
}
