# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
{
  options.builder.cachixPush = {
    enable = lib.mkEnableOption "publishing filtered build results to Cachix";
    cacheName = lib.mkOption {
      type = lib.types.str;
      description = "Cachix cache name";
    };
    authTokenFile = lib.mkOption {
      type = lib.types.str;
      description = "Runtime path to the Cachix authentication token file.";
    };
  };
  config = lib.mkIf (config.builder.enable && config.builder.cachixPush.enable) {
    systemd.services.cachix-push = {
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "nss-lookup.target"
      ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.cachix
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
        config.nix.package
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
        CACHIX_AUTH_TOKEN_FILE = config.builder.cachixPush.authTokenFile;
        CACHIX_CACHE_NAME = config.builder.cachixPush.cacheName;
        CACHIX_STATE_DIR = "/var/lib/cachix-push";
      };
    };
  };
}
