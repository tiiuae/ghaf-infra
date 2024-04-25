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
    listenAddress = "[::1]:8080";
    readOnly = true;
    extraArgs = [
      "--azureblob-env-auth"
    ];
    remote = ":azureblob:binary-cache-v1";
  };

  nix.settings.substituters = [
    # Configure Nix to use the bucket (through rclone-http) as a substitutor.
    # The public key is passed in externally.
    "http://localhost:8080"
  ];

  system.stateVersion = "23.05";
}
