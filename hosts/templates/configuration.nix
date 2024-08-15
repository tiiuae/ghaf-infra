# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    self.nixosModules.generic-disk-config
    self.nixosModules.service-openssh
    self.nixosModules.user-hrosten
  ];

  boot.loader.grub = {
    # no need to set devices, disko will add all devices that have a EF02
    # partition to the list already
    # devices = [ ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  nix.settings.experimental-features = "nix-command flakes";
  documentation.enable = false;

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
    pkgs.vim
  ];

  networking.firewall.enable = true;
  networking.enableIPv6 = false;
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "23.05";
}
