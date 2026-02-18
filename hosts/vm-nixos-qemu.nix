# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  vcpus ? 2,
  ram_gb ? 4,
  disk_gb ? 16,
  ...
}:
{
  virtualisation.vmVariant.virtualisation.graphics = true;
  virtualisation.vmVariant.virtualisation.cores = vcpus;
  virtualisation.vmVariant.virtualisation.memorySize = ram_gb * 1024;
  virtualisation.vmVariant.virtualisation.diskSize = disk_gb * 1024;
  virtualisation.vmVariant.virtualisation.writableStore = true;
  # Avoid rebuilding a temporary store image on every run; this significantly
  # reduces startup time.
  virtualisation.vmVariant.virtualisation.useNixStoreImage = false;
  virtualisation.vmVariant.virtualisation.mountHostNixStore = true;
  virtualisation.vmVariant.virtualisation.writableStoreUseTmpfs = false;
  virtualisation.vmVariant.virtualisation.qemu.consoles = [ "ttyS0,115200n8" ];
  virtualisation.vmVariant.virtualisation.qemu.options = [
    "-display none"
    "-serial mon:stdio"
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
