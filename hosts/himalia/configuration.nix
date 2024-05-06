# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  self,
  inputs,
  lib,
  pkgs,
  ...
}: {
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
      service-nginx
      service-node-exporter
      user-jrautiola
      user-cazfi
      user-karim
      user-tervis
      user-barna
      user-mika
    ]);
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
    hostName = "himalia";
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
          proxyPass = "http://127.0.0.1:3015";
        };
      };
    };
  };
}
