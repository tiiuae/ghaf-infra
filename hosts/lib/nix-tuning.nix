# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib }:
let
  # Keep binary units explicit to avoid repeated literals in callers.
  gib = 1024 * 1024 * 1024;
in
{
  # Exported for host modules that need byte conversion for custom values.
  inherit gib;

  # Compute Nix GC watermarks from total disk capacity.
  #
  # Defaults:
  # - min-free = max(20 GiB, 10% of disk)
  # - max-free = max(80 GiB, 30% of disk)
  # - caps for large disks: 160 GiB min-free, 512 GiB max-free
  #
  # Rationale:
  # - We trigger GC before free space becomes critically low (`min-free`).
  # - We free up to a higher target (`max-free`) to avoid frequent GC churn.
  # - Percentage-based targets scale naturally across host sizes.
  # - Floors avoid tiny thresholds on small disks.
  # - Caps prevent over-aggressive GC targets on multi-TiB disks.
  # - Keep max-free above min-free.
  mkDiskThresholds =
    diskGiB:
    let
      minPercent = 10;
      maxPercent = 30;
      minFloorGiB = 20;
      maxFloorGiB = 80;
      minCapGiB = 160;
      maxCapGiB = 512;

      minFromPercentGiB = builtins.div (diskGiB * minPercent) 100;
      maxFromPercentGiB = builtins.div (diskGiB * maxPercent) 100;
      cappedMinFreeGiB = lib.min minCapGiB (lib.max minFloorGiB minFromPercentGiB);
      cappedMaxFreeGiB = lib.min maxCapGiB (lib.max maxFloorGiB maxFromPercentGiB);
      maxFreeGiB = lib.max cappedMinFreeGiB cappedMaxFreeGiB;
    in
    {
      minFreeGiB = cappedMinFreeGiB;
      inherit maxFreeGiB;
      minFreeBytes = cappedMinFreeGiB * gib;
      maxFreeBytes = maxFreeGiB * gib;
    };

  # Bound concurrent builds by both CPU and RAM:
  # - cpu bound: at most half the cores used by concurrent jobs
  # - ram bound: at most one job per 4 GiB RAM
  # This is intentionally conservative to reduce OOM pressure and thrashing.
  mkMaxJobs = { cpus, ramGiB }: lib.max 1 (lib.min (builtins.div cpus 2) (builtins.div ramGiB 4));
}
