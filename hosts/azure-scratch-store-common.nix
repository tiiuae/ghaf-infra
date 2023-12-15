# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  utils,
  ...
}: {
  # Disable explicit resource disk handling in waagent.
  # We want to take control over it in initrd already.
  virtualisation.azure.agent.mountResourceDisk = false;

  boot.initrd.systemd = {
    # This requires systemd-in-initrd.
    enable = true;

    # We need the wipefs binary available in the initrd
    extraBin = {
      "wipefs" = "${pkgs.util-linux}/bin/wipefs";
    };

    # The resource disk comes pre-formatted with NTFS, not ext4.
    # Wipe the superblock if it's NTFS (and only then, to not wipe on every reboot).
    # Once we get `filesystems`-syntax to work again, we could delegate the mkfs
    # part to systemd-makefs (and make this `wantedBy` and `before` that makefs
    # unit).
    services.wipe-resource-disk = {
      description = "Wipe resource disk before makefs";
      requires = ["${utils.escapeSystemdPath "dev/disk/azure/resource-part1"}.device"];
      after = ["${utils.escapeSystemdPath "dev/disk/azure/resource-part1"}.device"];
      wantedBy = ["${utils.escapeSystemdPath "sysroot/mnt/resource"}.mount"];
      before = ["${utils.escapeSystemdPath "sysroot/mnt/resource"}.mount"];

      script = ''
        if [[ $(wipefs --output=TYPE -p /dev/disk/azure/resource-part1) == "ntfs" ]]; then
          echo "wiping resource disk (was ntfs)"
          wipefs -a /dev/disk/azure/resource-part1
          mkfs.ext4 /dev/disk/azure/resource-part1
        else
          echo "skip wiping resource disk (not ntfs)"
        fi
      '';
    };

    # Once /sysroot/mnt/resource is mounted, ensure the two .rw-store/
    # {work,store} directories that overlayfs is using are present.
    # The kernel doesn't create them on its own and fails the mount if they're
    # not present, so we set `wantedBy` and `before` to the .mount unit.
    services.setup-resource-disk = {
      description = "Setup resource disk after it's mounted";
      unitConfig.RequiresMountsFor = "/sysroot/mnt/resource";
      wantedBy = ["${utils.escapeSystemdPath "sysroot/nix/store"}.mount"];
      before = ["${utils.escapeSystemdPath "sysroot/nix/store"}.mount"];

      script = ''
        mkdir -p /sysroot/mnt/resource/.rw-store/{work,store}
      '';
    };

    # These describe the mountpoints inside the initrd
    # (/sysroot/mnt/resource, /sysroot/nix/store).
    # In the future, this should be moved to `filesystems`-syntax, so we can
    # make use of systemd-makefs and can write some things more concisely.
    mounts = [
      {
        where = "/sysroot/mnt/resource";
        what = "/dev/disk/azure/resource-part1";
        type = "ext4";
      }
      # describe the overlay mount
      {
        where = "/sysroot/nix/store";
        what = "overlay";
        type = "overlay";
        options = "lowerdir=/sysroot/nix/store,upperdir=/sysroot/mnt/resource/.rw-store/store,workdir=/sysroot/mnt/resource/.rw-store/work";
        wantedBy = ["initrd-fs.target"];
        before = ["initrd-fs.target"];
        requires = ["setup-resource-disk.service"];
        after = ["setup-resource-disk.service"];
        unitConfig.RequiresMountsFor = ["/sysroot" "/sysroot/mnt/resource"];
      }
    ];
  };
  # load the overlay kernel module
  boot.initrd.kernelModules = ["overlay"];
}
