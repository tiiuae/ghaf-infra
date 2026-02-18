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
  virtualisation.vmVariant.virtualisation.restrictNetwork = false;
  virtualisation.vmVariant.virtualisation.qemu.consoles = [ "ttyS0,115200n8" ];
  virtualisation.vmVariant.virtualisation.qemu.options = [
    "-display none"
    "-serial mon:stdio"
    "-device virtio-balloon"
    "-enable-kvm"
    # Ask QEMU to self-restrict host-side capabilities.
    "-sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny"
  ];
  virtualisation.vmVariant.services.openssh.hostKeys = [
    {
      # See nix/apps.nix: run-vm-with-share
      path = "/shared/secrets/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
  # Keep PID1 console output plain/stable on serial terminals.
  virtualisation.vmVariant.boot.kernelParams = [ "systemd.tty.term.console=dumb" ];
  # Keep serial console output stable by skipping agetty clear/reset sequences.
  virtualisation.vmVariant.services.getty.extraArgs = [
    "--noclear"
    "--noreset"
  ];
  virtualisation.vmVariant.services.getty.autologinUser = "root";
}
