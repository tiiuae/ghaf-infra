# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  disko.devices = {
    disk = {
      os = {
        device = "/dev/disk/by-id/nvme-KINGSTON_SNV3S2000G_50026B768715E152";
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
        type = "disk";
        device = "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_2TB_S4J4NX0W800239B";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/data1";
        };
      };

      data-disk2 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_2TB_S6P1NS0TA00562V";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/data2";
        };
      };
    };
  };
}
