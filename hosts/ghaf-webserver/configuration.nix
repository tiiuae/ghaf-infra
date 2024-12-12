# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  modulesPath,
  lib,
  pkgs,
  ...
}:
{
  sops.defaultSopsFile = ./secrets.yaml;

  imports =
    [
      ./disk-config.nix
      ./gala_uploaders.nix
      (modulesPath + "/profiles/qemu-guest.nix")
      inputs.sops-nix.nixosModules.sops
      inputs.disko.nixosModules.disko
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
      service-nginx
      user-cazfi
      user-jrautiola
    ]);

  # List packages installed in system profile
  environment.systemPackages = with pkgs; [ emacs ];

  # this server has been installed with 24.05
  system.stateVersion = lib.mkForce "24.05";

  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "ghaf-webserver";
    useDHCP = true;
  };

  boot = {
    # use predictable network interface names (eth0)
    kernelParams = [ "net.ifnames=0" ];
    loader.grub = {
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
  };

  services.nginx = {
    virtualHosts = {
      "vedenemo.dev" = {
        enableACME = true;
        forceSSL = true;
        root = "/var/www/vedenemo.dev";
        default = true;
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "trash@unikie.com";
  };
}
