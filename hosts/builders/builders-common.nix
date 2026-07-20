# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.builder.tuning;
  tuning = import ../lib/nix-tuning.nix { inherit lib; };
  build = tuning.mkBuildLimits {
    inherit (cfg) cpus ramGiB;
  };
  disk = if cfg.diskGiB == null then null else tuning.mkDiskThresholds cfg.diskGiB;
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

  config = lib.mkMerge [
    {
      # Specifies the maximum number of concurrent unauthenticated connections to the SSH daemon.
      # The default of 10 is not enough when multiple clients are building
      # at the same time and can result in dropped connections
      services.openssh.settings.MaxStartups = 100;

      # Increase the maximum number of open files user limit, see ulimit
      security.pam.loginLimits = [
        {
          domain = "*";
          item = "nofile";
          type = "-";
          value = "8192";
        }
      ];
    }
    (lib.mkIf cfg.enable {
      nix.settings = {
        max-jobs = lib.mkForce build.maxJobs;
        cores = lib.mkForce build.cores;
      }
      // lib.optionalAttrs (disk != null) {
        min-free = lib.mkForce disk.minFreeBytes;
        max-free = lib.mkForce disk.maxFreeBytes;
      };
    })
  ];
}
