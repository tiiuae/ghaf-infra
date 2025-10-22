# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  pkgs,
  inputs,
  ...
}:
{

  imports =
    [
      ./disk-config.nix
      ../hetzner-cloud.nix
      inputs.sops-nix.nixosModules.sops
      inputs.disko.nixosModules.disko
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
      service-nginx
      team-devenv
    ]);

  sops.defaultSopsFile = ./secrets.yaml;

  # List packages installed in system profile
  environment.systemPackages = with pkgs; [ emacs ];

  system.stateVersion = lib.mkForce "24.05";
  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "ghaf-webserver";

  services.nginx.virtualHosts."vedenemo.dev" = {
    enableACME = true;
    forceSSL = true;
    default = true;

    locations."/" = {
      return = "301 https://archive.vedenemo.dev";
    };

    locations."/files/gala/" = {
      extraConfig = ''
        rewrite ^/files/gala/(.*)$ https://hel1.your-objectstorage.com/gala/$1 permanent;
      '';
    };
  };
}
