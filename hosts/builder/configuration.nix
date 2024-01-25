# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../azure-common-2.nix
    self.nixosModules.service-openssh
    self.nixosModules.service-remote-build
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Run a read-only HTTP webserver proxying to the "binary-cache-v1" storage
  # container via http://localhost:8080.
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
      ExecStart =
        "${pkgs.rclone}/bin/rclone "
        + "serve http "
        + "--azureblob-env-auth "
        + "--read-only "
        + "--addr localhost:8080 "
        + ":azureblob:binary-cache-v1";
      EnvironmentFile = "/var/lib/rclone-http/env";
    };
  };

  # Configure Nix to use this as a substitutor, and the public key used for signing.
  nix.settings.trusted-public-keys = [
    "ghaf-jenkins:5OXpzoevBwH4sBR0S0HaIQCik2adrOrGawIXO+WADCk="
  ];
  nix.settings.substituters = [
    "http://localhost:8080"
  ];

  system.stateVersion = "23.05";
}
