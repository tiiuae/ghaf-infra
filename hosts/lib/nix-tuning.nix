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
  # Rationale:
  # - We trigger GC before free space becomes critically low (`min-free`).
  # - We free up to a higher target (`max-free`) to avoid frequent GC churn.
  # - Percentages (10% / 30%) scale with disk size, while fixed floors
  #   (20 GiB / 80 GiB) protect smaller disks.
  mkDiskThresholds =
    diskGiB:
    let
      minFreeGiB = lib.max 20 (builtins.div (diskGiB * 10) 100);
      maxFreeGiB = lib.max 80 (builtins.div (diskGiB * 30) 100);
    in
    {
      inherit minFreeGiB maxFreeGiB;
      minFreeBytes = minFreeGiB * gib;
      maxFreeBytes = maxFreeGiB * gib;
    };

  # Bound concurrent builds by both CPU and RAM:
  # - cpu bound: at most half the cores used by concurrent jobs
  # - ram bound: at most one job per 4 GiB RAM
  # This is intentionally conservative to reduce OOM pressure and thrashing.
  mkMaxJobs = { cpus, ramGiB }: lib.max 1 (lib.min (builtins.div cpus 2) (builtins.div ramGiB 4));
}
