# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  self,
  inputs,
  lib,
  config,
  ...
}: {
  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets.cache-sig-key.owner = "root";

  imports = lib.flatten [
    (with inputs; [
      sops-nix.nixosModules.sops
      disko.nixosModules.disko
    ])
    (with self.nixosModules; [
      common
      qemu-common
      ficolo-common
      service-openssh
      service-binary-cache
      service-nginx
      service-node-exporter
      user-jrautiola
      user-cazfi
      user-hydra
      user-tervis
    ])
    ./disk-config.nix
  ];

  nix.settings = {
    # we don't want the cache to be a substitutor for itself
    substituters = lib.mkForce ["https://cache.nixos.org/"];
    trusted-users = ["hydra"];
  };

  # do not run garbage collection, we have enough disk space
  nix.gc.automatic = lib.mkForce false;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  networking = {
    hostName = "binarycache";
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "trash@unikie.com";
  };

  services.nginx = {
    virtualHosts = {
      "cache.vedenemo.dev" = {
        enableACME = true;
        forceSSL = true;
        default = true;
        locations."/" = {
          proxyPass = "http://${config.services.nix-serve.bindAddress}:${toString config.services.nix-serve.port}";
        };
      };
    };
  };
}
