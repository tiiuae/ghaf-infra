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
      user-jrautiola
      user-cazfi
      user-karim
    ])
    ./disk-config.nix
  ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
   # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    git
    emacs
  ];
  # docker daemon running
  virtualisation.docker.enable=true;

  networking = {
    hostName = "prbuilder";
    nameservers = ["1.1.1.1" "8.8.8.8"];
  };
}
