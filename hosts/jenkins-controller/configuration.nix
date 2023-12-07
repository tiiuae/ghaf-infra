# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  ...
}: {
  imports = [
    ../azure-common-2.nix
    self.nixosModules.service-openssh
  ];

  services.jenkins = {
    enable = true;
    listenAddress = "localhost";
    port = 8080;
    withCLI = true;
  };

  # set StateDirectory=jenkins, so state volume has the right permissions
  # https://github.com/NixOS/nixpkgs/pull/272679
  systemd.services.jenkins.serviceConfig.StateDirectory = "jenkins";

  # TODO: deploy reverse proxy, sort out authentication (SSO?)

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  system.stateVersion = "23.05";
}
