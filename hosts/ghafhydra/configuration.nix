# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  config,
  ...
}: {
  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets.hydra-admin-password.owner = "hydra";
  sops.secrets.id_buildfarm = {};
  sops.secrets.id_buildfarm.owner = "hydra-queue-runner";
  sops.secrets.cache-sig-key.owner = "root";

  imports = lib.flatten [
    (with inputs; [
      sops-nix.nixosModules.sops
      disko.nixosModules.disko
    ])
    (with self.nixosModules; [
      common
      azure-common
      generic-disk-config
      service-hydra
      service-openssh
      service-binary-cache
      service-nginx
      user-hrosten
      user-tervis
    ])
  ];

  networking.hostName = "ghafhydra";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  boot.loader.grub = {
    devices = ["/dev/sda"];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # TODO: have a separate configuration for ghafhydra-dev?
  # Ref: https://nixos.org/manual/nixos/stable/#module-security-acme
  security.acme.defaults.email = "trash@unikie.com";
  security.acme.acceptTerms = true;
  services.nginx = {
    virtualHosts = {
      "ghafhydra.northeurope.cloudapp.azure.com" = {
        forceSSL = true;
        enableACME = true;
        locations."/".proxyPass = "http://localhost:${toString config.services.hydra.port}";
      };
    };
  };

  # TODO: demo with static IP:
  networking.useDHCP = false;
  networking.nameservers = ["1.1.1.1" "8.8.8.8"];
  networking.defaultGateway = "10.0.2.1";
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.0.2.4";
      prefixLength = 24;
    }
  ];
}
