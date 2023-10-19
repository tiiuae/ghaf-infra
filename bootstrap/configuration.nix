# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  inputs,
  lib,
  config,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ../hosts/generic-disk-config.nix
    ../services/openssh/openssh.nix
    ../users/hrosten.nix
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

  # TODO: needs refinement
  networking.firewall.enable = true;
  networking.enableIPv6 = false;
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "23.05";
}
