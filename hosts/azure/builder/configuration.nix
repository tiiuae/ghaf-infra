# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  ...
}: {
  imports = [
    ../../azure-common.nix
    self.nixosModules.service-openssh
    self.nixosModules.service-remote-build
    self.nixosModules.service-rclone-http
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  services.rclone-http = {
    enable = true;
    readOnly = true;
    remote = ":azureblob:binary-cache-v1";
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
