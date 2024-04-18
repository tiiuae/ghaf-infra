# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}:
with lib; let
  cfg = config.services.rclone-http;
in {
  options.services.rclone-http = {
    enable = mkEnableOption "rclone-http service";

    listenAddress = mkOption {
      type = types.str;
      default = "localhost:8080";
      description = "IPaddress:Port, :Port or unix:///path/to/socket to bind server to";
    };

    readOnly = mkOption {
      type = types.bool;
      default = false;
      description = "Only allow read-only access";
    };

    protocol = mkOption {
      type = types.enum ["http" "webdav"];
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
      after = ["network.target"];
      requires = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "notify";
        Restart = "always";
        RestartSec = 2;
        DynamicUser = true;
        RuntimeDirectory = "rclone-http";
        # TODO: migrate setting these values to terraform/custom-nixos.nix
        EnvironmentFile = "/var/lib/rclone-http/env";

        ExecStart =
          "${pkgs.rclone}/bin/rclone "
          + "serve ${cfg.protocol} "
          + "--azureblob-env-auth "
          + "${optionalString cfg.readOnly "--read-only "}"
          + "--addr ${cfg.listenAddress} "
          + "${cfg.remote}";
      };
    };
  };
}
