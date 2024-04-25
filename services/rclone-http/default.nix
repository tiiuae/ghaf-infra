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

  # If rebasing this on rclone 1.64.2, which is what nixpkgs point to,
  # it introduces a change in go.mod/go.sum (not present in mainline),
  # which would require overriding vendorHash, which is a bit involved due to
  # https://github.com/NixOS/nixpkgs/issues/86349.
  # Instead of doing this, just vendor in a (simplified) expression.
  rclone = with pkgs;
    buildGoModule rec {
      pname = "rclone";
      version = "1.66.0";

      src = fetchFromGitHub {
        owner = "rclone";
        repo = "rclone";
        rev = "v${version}";
        hash = "sha256-75RnAROICtRUDn95gSCNO0F6wes4CkJteNfUN38GQIY=";
      };

      patches = [
        # https://github.com/rclone/rclone/pull/7801
        ../../nix/patches/rclone-socket-activation.patch
      ];

      vendorHash = "sha256-zGBwgIuabLDqWbutvPHDbPRo5Dd9kNfmgToZXy7KVgI=";

      subPackages = ["."];

      outputs = ["out" "man"];

      nativeBuildInputs = [installShellFiles makeWrapper];

      ldflags = ["-s" "-w" "-X github.com/rclone/rclone/fs.Version=${version}"];

      postInstall = let
        rcloneBin =
          if stdenv.buildPlatform.canExecute stdenv.hostPlatform
          then "$out"
          else lib.getBin buildPackages.rclone;
      in ''
        installManPage rclone.1
        for shell in bash zsh fish; do
          ${rcloneBin}/bin/rclone genautocomplete $shell rclone.$shell
          installShellCompletion rclone.$shell
        done

        # filesystem helpers
        ln -s $out/bin/rclone $out/bin/rclonefs
        ln -s $out/bin/rclone $out/bin/mount.rclone
      '';
    };
in {
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
      serviceConfig = {
        Type = "notify";
        Restart = "always";
        RestartSec = 2;
        DynamicUser = true;
        RuntimeDirectory = "rclone-http";
        EnvironmentFile = "/var/lib/rclone-http/env";
        ExecStart = concatStringsSep " " ([
            "${rclone}/bin/rclone"
            "serve"
            cfg.protocol
          ]
          ++ cfg.extraArgs
          ++ [cfg.remote]);
      };
    };
    systemd.sockets.rclone-http = {
      wantedBy = ["sockets.target"];
      socketConfig.ListenStream = cfg.listenAddress;
    };
  };
}
