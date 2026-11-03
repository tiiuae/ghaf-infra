# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
{
  imports = [ ./caches.nix ];

  options.nix.gc.keepSystemGenerations = lib.mkOption {
    type = lib.types.ints.positive;
    default = 3;
    description = "Number of system profile generations to keep when pruning before automatic garbage collection.";
  };

  config = lib.mkMerge [
    {
      nix = {
        settings = {
          trusted-users = [
            "root"
            "@wheel"
          ];
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          builders-use-substitutes = lib.mkDefault true;
          connect-timeout = lib.mkDefault 5;
          log-lines = lib.mkDefault 25;
        };
        daemonCPUSchedPolicy = lib.mkDefault "batch";
        daemonIOSchedClass = lib.mkDefault "idle";
        daemonIOSchedPriority = lib.mkDefault 7;
      };
      systemd.services.nix-daemon.serviceConfig.OOMScoreAdjust = lib.mkDefault 250;
    }
    (lib.mkIf config.nix.gc.automatic {
      nix.settings = {
        min-free = lib.mkDefault (20 * 1024 * 1024 * 1024);
        max-free = lib.mkDefault (200 * 1024 * 1024 * 1024);
        min-free-check-interval = lib.mkDefault 5;
      };
      systemd.services.nix-gc = {
        preStart = ''
          ${config.nix.package}/bin/nix-env --delete-generations +${toString config.nix.gc.keepSystemGenerations} --profile /nix/var/nix/profiles/system
        '';
        serviceConfig.Restart = lib.mkDefault "on-failure";
      };
    })
  ];
}
