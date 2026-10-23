# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  tuning = import ../../hosts/lib/nix-tuning.nix { inherit lib; };
  build = tuning.mkBuildLimits {
    inherit (config.builder.tuning) cpus ramGiB;
  };
  disk =
    if config.builder.tuning.diskGiB == null then
      null
    else
      tuning.mkDiskThresholds config.builder.tuning.diskGiB;
in
{
  options.builder.tuning = {
    enable = lib.mkEnableOption "builder-specific Nix tuning";
    cpus = lib.mkOption {
      type = lib.types.ints.positive;
      description = "Number of logical CPUs available to Nix builds.";
    };
    ramGiB = lib.mkOption {
      type = lib.types.ints.positive;
      description = "Memory available to Nix builds in GiB.";
    };
    diskGiB = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Capacity of the Nix store filesystem in GiB.";
    };
  };

  config = lib.mkIf (config.builder.enable && config.builder.tuning.enable) {
    nix.settings = {
      max-jobs = lib.mkForce build.maxJobs;
      cores = lib.mkForce build.cores;
    }
    // lib.optionalAttrs (disk != null) {
      min-free = lib.mkForce disk.minFreeBytes;
      max-free = lib.mkForce disk.maxFreeBytes;
    };
  };
}
