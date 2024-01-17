# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = lib.flatten [
    (with inputs; [
      nix-serve-ng.nixosModules.default
      disko.nixosModules.disko
    ])
    (with self.nixosModules; [
      common
      qemu-common
      service-openssh
      service-node-exporter
      user-jrautiola
      user-cazfi
      user-karim
      user-tervis
      user-barna
      user-mika
    ])
    ./disk-config.nix
  ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    git
    emacs
    screen
    (python310.withPackages (ps:
      with ps; [
        requests
        schedule
        pygithub
        aiohttp
      ]))
  ];
  # docker daemon running
  virtualisation.docker.enable = true;

  networking = {
    hostName = "prbuilder";
    nameservers = ["1.1.1.1" "8.8.8.8"];
  };
}
