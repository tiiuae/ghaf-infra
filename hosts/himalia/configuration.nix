# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  self,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports =
    [
      ./disk-config.nix
      inputs.nix-serve-ng.nixosModules.default
      inputs.disko.nixosModules.disko
    ]
    ++ (with self.nixosModules; [
      common
      qemu-common
      ficolo-common
      service-openssh
      user-jrautiola
      user-cazfi
      user-karim
      user-barna
      user-mika
    ]);

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking.hostName = "himalia";

  # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    git
    emacs
    screen
    (python310.withPackages (
      ps: with ps; [
        requests
        schedule
        pygithub
        aiohttp
      ]
    ))
  ];

  # docker daemon running
  virtualisation.docker.enable = true;

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };
}
