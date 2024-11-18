# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  self,
  inputs,
  lib,
  ...
}:
{
  sops.defaultSopsFile = ./secrets.yaml;

  imports =
    [
      ./disk-config.nix
      inputs.sops-nix.nixosModules.sops
      inputs.disko.nixosModules.disko
    ]
    ++ (with self.nixosModules; [
      common
      ficolo-common
      service-openssh
      user-jrautiola
      user-cazfi
      user-hrosten
      user-mkaapu
      user-avnik
    ]);

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking.hostName = "binarycache";

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };
}
