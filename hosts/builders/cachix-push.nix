# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.cachix-push;
in
{
  options.cachix-push = {
    cacheName = lib.mkOption {
      type = lib.types.str;
      description = "Cachix cache name";
    };
  };
  config = {
    systemd.services.cachix-push = {
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "nss-lookup.target"
      ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        cachix
        coreutils
        findutils
        gnugrep
      ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        # Try re-start at 30 second intervals.
        RestartSec = 30;
        # Do not loop forever on permanent startup misconfiguration such as a
        # missing or unusable cachix auth token.
        RestartPreventExitStatus = [
          10
          11
          12
        ];
        StateDirectory = "cachix-push";
      };
      # Allow unlimited restart attempts
      unitConfig.StartLimitBurst = 0;
      script = builtins.readFile ./cachix-push.sh;
      environment = {
        CACHIX_AUTH_TOKEN_FILE = "${config.sops.secrets.cachix-auth-token.path}";
        CACHIX_CACHE_NAME = cfg.cacheName;
        CACHIX_STATE_DIR = "/var/lib/cachix-push";
      };
    };
  };
}
