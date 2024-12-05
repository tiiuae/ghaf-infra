# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.services.rclone-http;
in
{
  options.services.rclone-http = {
    enable = mkEnableOption "rclone-http service";

    listenAddress = mkOption {
      type = types.str;
      description = "The address to listen on. Accepts formats from https://www.freedesktop.org/software/systemd/man/latest/systemd.socket.html#ListenStream=.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      description = ''
        Additional command-line arguments to pass to rclone.
      '';
    };

    protocol = mkOption {
      type = types.enum [
        "http"
        "webdav"
      ];
      default = "http";
      description = "The protocol to serve the remote over";
    };

    remote = mkOption {
      type = types.str;
      description = "The remote to serve";
    };
  };

  config = mkIf cfg.enable {
    # Run a read-only HTTP webserver proxying to an rclone remote at the configured address
    # This relies on IAM to grant access to the storage container.
    systemd.services.rclone-http = {
      after = [ "network.target" ];
      serviceConfig = {
        Type = "notify";
        Restart = "always";
        RestartSec = 2;
        DynamicUser = true;
        RuntimeDirectory = "rclone-http";
        EnvironmentFile = "/var/lib/rclone-http/env";
        ExecStart = concatStringsSep " " (
          [
            "${pkgs.rclone}/bin/rclone"
            "serve"
            cfg.protocol
          ]
          ++ cfg.extraArgs
          ++ [ cfg.remote ]
        );
      };
    };
    systemd.sockets.rclone-http = {
      wantedBy = [ "sockets.target" ];
      socketConfig.ListenStream = cfg.listenAddress;
    };
  };
}
