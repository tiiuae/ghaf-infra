# SPDX-FileCopyrightText: 2023-2024 Technology Innovation Institute (TII)
# SPDX-License-Identifier: Apache-2.0
#
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
      ficolo-common
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
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "trash@unikie.com";
  };

  services.nginx = {
    virtualHosts = {
      "himalia.vedenemo.dev" = {
        enableACME = true;
        forceSSL = true;
        default = true;
        locations."/" = {
          proxyPass = "http:127.0.0.1:3015";
        };
      };
    };
  };
}
