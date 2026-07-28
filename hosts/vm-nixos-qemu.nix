# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  vcpus ? 2,
  ram_gb ? 4,
  disk_gb ? 16,
  mount_host_nix_store ? true,
  use_nix_store_image ? (!mount_host_nix_store),
  ...
}:
{
  virtualisation.vmVariant = {
    virtualisation = {
      graphics = true;
      cores = vcpus;
      memorySize = ram_gb * 1024;
      diskSize = disk_gb * 1024;
      writableStore = true;
      # Host store mount is faster to start; store image keeps guest independent.
      useNixStoreImage = use_nix_store_image;
      mountHostNixStore = mount_host_nix_store;
      writableStoreUseTmpfs = false;
      restrictNetwork = false;
      qemu = {
        consoles = [ "ttyS0,115200n8" ];
        options = [
          "-display none"
          "-serial mon:stdio"
          "-device virtio-balloon"
          "-enable-kvm"
          # Ask QEMU to self-restrict host-side capabilities.
          "-sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny"
        ];
      };
    };

    services = {
      openssh.hostKeys = [
        {
          # See nix/apps.nix: run-vm-with-share
          path = "/shared/secrets/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];

      # Keep serial console output stable by skipping agetty clear/reset sequences.
      getty = {
        extraArgs = [
          "--noclear"
          "--noreset"
        ];
        autologinUser = "root";
      };
    };

    # Keep PID1 console output plain/stable on serial terminals.
    boot.kernelParams = [ "systemd.tty.term.console=dumb" ];

    # The VM runs headless (`-display none`), so tty1 is unused. Disabling its
    # autovt avoids a boot-time race where tty1 and ttyS0 both autologin root and
    # contend on lastlog2.db.
    systemd.services."autovt@tty1".enable = false;
  };
}
