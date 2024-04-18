# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
with lib; let
  tvl-kit = import "${inputs.tvl-kit.outPath}" {inherit pkgs;};
  cfg = config.services.jenkins-upload-artifacts;
in {
  options.services.jenkins-upload-artifacts = {
    enable = mkEnableOption "The Jenkins upload artifacts service";

    listenAddress = mkOption {
      type = types.str;
      description = "IPaddress:Port, :Port to bind the jenkins-upload-artifacts to";
    };

    remote = mkOption {
      type = types.str;
      description = "The rclone remote to serve";
    };
  };

  config = mkIf cfg.enable {
    # Run a webdav HTTP webserver proxying to an rclone remote.
    # This listens on /run/jenkins-upload-artifacts-rclone/sock.
    systemd.services.jenkins-upload-artifacts-rclone = {
      after = ["network.target"];
      requires = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "notify";
        Restart = "always";
        RestartSec = 2;
        DynamicUser = true;
        RuntimeDirectory = "jenkins-upload-artifacts-rclone";
        # TODO: migrate setting these values to terraform/custom-nixos.nix
        EnvironmentFile = "/var/lib/rclone-http/env";

        ExecStart =
          "${pkgs.rclone}/bin/rclone "
          + "serve webdav "
          + "--azureblob-env-auth "
          + "--addr %t/jenkins-upload-artifacts-rclone/sock "
          + "${cfg.remote}";

        # TODO: ensure socket permissions give only jenkins-upload-artifacts access,
        # not the jenkins user.
        # FUTUREWORK: move rclone to socket activation too https://github.com/rclone/rclone/issues/7783
      };
    };

    # Run the HTTP uploader service itself, using systemd socket activation to
    # start when needed.
    systemd.services.jenkins-upload-artifacts = let
      svc = tvl-kit.buildGo.program {
        name = "jenkins-upload-artifacts";
        srcs = [./jenkins-upload-artifacts.go];
      };
    in {
      after = ["rclone-http.service"];
      requires = ["rclone-http.service"];
      serviceConfig.ExecStart = "${svc}/bin/jenkins-upload-artifacts -target-url=unix:///run/jenkins-upload-artifacts-rclone/sock";
    };

    # Bind on the listenAddress provided in the config.
    systemd.sockets.jenkins-upload-artifacts = {
      wantedBy = ["sockets.target"];
      socketConfig.ListenStream = "${cfg.listenAddress}";
    };
  };
}
