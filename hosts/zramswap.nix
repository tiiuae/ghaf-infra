# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  ...
}:
{
  config = {
    # Enable zramSwap: https://search.nixos.org/options?show=zramSwap.enable
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      # Increasing the zramSwap size up to 150% should be fine.
      # Ref: https://github.com/NixOS/nixpkgs/issues/103106
      memoryPercent = lib.mkDefault 150;
    };
    # https://wiki.archlinux.org/title/Zram#Optimizing_swap_on_zram:
    boot.kernel.sysctl = {
      "vm.swappiness" = 180;
      "vm.watermark_boost_factor" = 0;
      "vm.watermark_scale_factor" = 125;
      "vm.page-cluster" = 0;
    };
  };
}
