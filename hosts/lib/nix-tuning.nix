# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib }:
let
  # Keep binary units explicit to avoid repeated literals in callers.
  gib = 1024 * 1024 * 1024;
in
rec {
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

  # Bound concurrent builds by both CPU and RAM, and pair that with the number
  # of cores exposed to each derivation through NIX_BUILD_CORES.
  #
  # Start from a conservative job budget:
  # - cpu bound: at most half the host CPUs as concurrent jobs
  # - ram bound: roughly one job per 4 GiB RAM, rounded up
  #
  # Then choose a wider per-job core count while retaining enough job
  # concurrency to keep the build graph fed. The aggregate CPU budget is capped
  # at the host CPU count.
  mkBuildLimits =
    { cpus, ramGiB }:
    let
      ceilDiv = x: y: builtins.div (x + y - 1) y;
      jobBudget = lib.max 1 (lib.min (builtins.div cpus 2) (builtins.div (ramGiB + 3) 4));
      aggregateCoreBudget = lib.min cpus (jobBudget * 2);
      minJobs = lib.min jobBudget (lib.max 1 (lib.max 4 (ceilDiv jobBudget 3)));
      cores = lib.max 1 (builtins.div aggregateCoreBudget minJobs);
      maxJobs = lib.max 1 (lib.min jobBudget (builtins.div aggregateCoreBudget cores));
    in
    {
      inherit cores maxJobs;
    };

  mkMaxJobs = args: (mkBuildLimits args).maxJobs;
}
