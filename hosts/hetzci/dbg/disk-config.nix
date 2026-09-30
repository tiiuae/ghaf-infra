# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
let
  writablePartUUID = "6e7dcf69-bd9a-4b1e-b6e2-62d8921112cd";
  luks = import ../../lib/baseline-reset-luks.nix;
in
{
  services.baseline-reset.rootWritablePartUUID = writablePartUUID;
  disko.devices.disk.os = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_52685044";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          type = "EF02";
          size = "1M";
        };
        ESP = {
          type = "EF00";
          size = "1024M";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        baseline = {
          size = "64G";
          content = {
            type = "btrfs";
            subvolumes = {
              "@persist".mountpoint = "/var/lib/baseline-reset";
              "@lower" = {
                mountpoint = "/.baseline-reset/lower";
                mountOptions = [ "ro" ];
              };
            };
          };
        };
        writable = {
          size = "100%";
          uuid = writablePartUUID;
          content = luks "baseline-root" "/";
        };
      };
    };
  };
}
