# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
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

  # build4 specific configuration

  sops.defaultSopsFile = ./secrets.yaml;

  networking.hostName = "build4";
}
