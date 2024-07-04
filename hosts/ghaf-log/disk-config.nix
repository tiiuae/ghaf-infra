# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  disko.devices.disk = {
    os = {
      device = "/dev/disk/by-path/pci-0000:06:00.0-scsi-0:0:0:0";
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
            size = "512M";
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
    # hetzner block storage, must be attached from cloud gui
    block = {
      device = "/dev/disk/by-id/scsi-0HC_Volume_100874627";
      type = "disk";
      content = {
        type = "filesystem";
        format = "ext4";
        mountpoint = "/data";
      };
    };
  };
}
