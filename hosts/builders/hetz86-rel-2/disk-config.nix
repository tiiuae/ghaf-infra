# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
let
  rootWritablePartUUID = "a18cfe67-9bf7-4d15-8942-dc9852da47d6";
  nixWritablePartUUID = "9e83bb51-4bd9-4ee0-a9ea-4641588551fc";
  luks = import ../../lib/baseline-reset-luks.nix;
in
{
  services.baseline-reset = {
    inherit rootWritablePartUUID nixWritablePartUUID;
  };
  disko.devices.disk = {
    nvme0 = {
      device = "/dev/disk/by-id/nvme-eui.000000000000000400a075254e93856f";
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
              };
            };
          };
          writable = {
            size = "100%";
            uuid = rootWritablePartUUID;
            content = luks "baseline-root" "/";
          };
        };
      };
    };

    nvme1 = {
      device = "/dev/disk/by-id/nvme-eui.000000000000000400a075254e93857a";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          baseline = {
            size = "64G";
            content = {
              type = "btrfs";
              subvolumes."@lower" = {
                mountpoint = "/.baseline-reset/lower";
                mountOptions = [ "ro" ];
              };
            };
          };
          writable = {
            size = "100%";
            uuid = nixWritablePartUUID;
            content = luks "baseline-nix" "/.baseline-reset/nix-writable";
          };
        };
      };
    };
  };
}
