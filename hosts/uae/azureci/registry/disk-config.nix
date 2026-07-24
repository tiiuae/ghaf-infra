# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  disko.devices.disk = {
    os = {
      device = "/dev/disk/by-id/scsi-3600224802f7903d421d1e5228d90c98f";
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
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
    data-disk1 = {
      device = "/dev/disk/by-id/scsi-3600224804d4dbfa9e813969dda6e0606";
      type = "disk";
      content = {
        type = "filesystem";
        format = "xfs";
        mountpoint = "/var/lib/zot";
      };
    };
  };
}
