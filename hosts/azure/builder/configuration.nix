# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../../azure-common.nix
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
  # TODO: remove cache.vedenemo.dev substituter
  nix.settings.trusted-public-keys = [
    "cache.vedenemo.dev:8NhplARANhClUSWJyLVk4WMyy1Wb4rhmWW2u8AejH9E="
  ];
  nix.settings.substituters = [
    # Configure Nix to use the bucket (through rclone-http) as a substitutor.
    # The public key is passed in externally.
    "http://localhost:8080"
    "https://cache.vedenemo.dev"
  ];

  system.stateVersion = "23.05";
}
