# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
#
# This configuration is currently not used, but kept here for reference.
# The reason this isn't currently used is that the 'setup-resource-disk'
# service that's setup in this file systematically fails on the first
# boot-up, which then cascades other service failures.
# It fails to mount the resource disk in initrd on the first boot.
#
# The changes from this file were originally introduced in the following PR
# https://github.com/tiiuae/ghaf-infra/pull/35 in commit:
# https://github.com/tiiuae/ghaf-infra/commit/7a7a1e40b24b6776c70f7e030c7608ed90b40e45
# Later, the scratch disk was disabled due to the reason explained above
# and worked-around by mounting /nix/store on the osdisk with the following change:
# https://github.com/tiiuae/ghaf-infra/commit/f143ac92517a3588d038e88eda09f19471e42de3
#
# Note: if we decice to re-enable this config at some later time, it's worth
# mentioning that originally this configuration did not work on nixos-23.11
# as described here:
# https://github.com/tiiuae/ghaf-infra/commit/e9b7db1c02c459c0b8d54a4d65aac1d400f4035d
#
# At the time of writing, ghaf-infra main branch follows 23.11:
# https://github.com/tiiuae/ghaf-infra/pull/74/commits/dd42bf9191f8133aaedb65aebb5756d8b4d567af
# which means these changes would not work without also changing the ghaf-infra
# nixpkgs reference.
#
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
