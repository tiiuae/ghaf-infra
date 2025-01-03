# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  self,
  inputs,
  lib,
  config,
  ...
}:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets.cache-sig-key.owner = "root";

  imports =
    [
      ./disk-config.nix
      inputs.sops-nix.nixosModules.sops
      inputs.disko.nixosModules.disko
    ]
    ++ (with self.nixosModules; [
      common
      qemu-common
      ficolo-common
      service-openssh
      service-binary-cache
      service-nginx
      user-jrautiola
      user-cazfi
      user-hrosten
      user-avnik
    ]);

  nix.settings = {
    # we don't want the cache to be a substitutor for itself
    substituters = lib.mkForce [ "https://cache.nixos.org/" ];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  networking = {
    hostName = "binarycache";
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "trash@unikie.com";
  };

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };

  services.nginx = {
    recommendedZstdSettings = true;
    virtualHosts = {
      "cache.vedenemo.dev" = {
        enableACME = true;
        forceSSL = true;
        default = true;
        locations."/" = {
          proxyPass = "http://${config.services.nix-serve.bindAddress}:${toString config.services.nix-serve.port}";
          extraConfig = ''
            zstd on;
            zstd_types application/x-nix-archive;
          '';
        };
      };
    };
  };
}
