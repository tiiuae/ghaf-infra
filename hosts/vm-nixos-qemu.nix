# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  vcpus ? 2,
  ram_gb ? 4,
  disk_gb ? 16,
  ...
}:
{
  virtualisation.vmVariant.virtualisation.graphics = false;
  virtualisation.vmVariant.virtualisation.cores = vcpus;
  virtualisation.vmVariant.virtualisation.memorySize = ram_gb * 1024;
  virtualisation.vmVariant.virtualisation.diskSize = disk_gb * 1024;
  virtualisation.vmVariant.virtualisation.writableStore = true;
  virtualisation.vmVariant.virtualisation.useNixStoreImage = true;
  virtualisation.vmVariant.virtualisation.mountHostNixStore = false;
  virtualisation.vmVariant.virtualisation.writableStoreUseTmpfs = false;
  virtualisation.vmVariant.virtualisation.qemu.options = [
    "-device virtio-balloon"
    "-enable-kvm"
  ];
  virtualisation.vmVariant.services.openssh.hostKeys = [
    {
      # See nix/apps.nix: run-vm-with-share
      path = "/shared/secrets/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
  virtualisation.vmVariant.services.getty.autologinUser = "root";
}
