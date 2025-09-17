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
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        cachix
        diffutils
      ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        # Try re-start at 30 seconds intervals.
        # If there are more than 3 restart attempts in a 240 second interval,
        # wait for the 240 second interval to pass before another re-try.
        RestartSec = 30;
        StartLimitBurst = 3;
        StartLimitInterval = 240;
      };
      script = builtins.readFile ./cachix-push.sh;
      environment = {
        CACHIX_AUTH_TOKEN_FILE = "${config.sops.secrets.cachix-auth-token.path}";
        CACHIX_CACHE_NAME = cfg.cacheName;
      };
    };
  };
}
