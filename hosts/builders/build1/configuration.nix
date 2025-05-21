# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  config,
  ...
}:
{
  imports =
    [
      ../ficolo.nix
      ../cross-compilation.nix
      ../builders-common.nix
      inputs.sops-nix.nixosModules.sops
    ]
    ++ (with self.nixosModules; [
      service-openssh
      team-devenv
      user-github
      user-remote-build
    ]);

  # build1 specific configuration

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets.cachix-auth-token.owner = "root";
  };

  networking.hostName = "build1";

  services.cachix-watch-store = {
    enable = true;
    verbose = true;
    cacheName = "ghaf-dev";
    cachixTokenFile = config.sops.secrets.cachix-auth-token.path;
  };
}
