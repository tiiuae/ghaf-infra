# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  self,
  inputs,
  pkgs,
  ...
}: let
  # Vendored in until our nixpkgs pin includes https://github.com/NixOS/nixpkgs/pull/302833.
  brainstem = pkgs.callPackage ./brainstem.nix {};
in {
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ]
    ++ (with inputs; [
      sops-nix.nixosModules.sops
      disko.nixosModules.disko
    ])
    ++ (with self.nixosModules; [
      common
      service-openssh
      user-tervis
      user-vjuntunen
      user-flokli
      user-jrautiola
    ]);

  # Bootloader.
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  networking = {
    hostName = "testagent";
    useNetworkd = true;
  };

  # Enable Acroname USB Smart switch support.
  services.udev.packages = [brainstem];

  environment.systemPackages = [
    inputs.robot-framework.packages.${pkgs.system}.ghaf-robot
    brainstem
  ];

  # Disable suspend and hibernate - systemd settings
  services.logind.extraConfig = ''
    HandleSuspendKey=ignore
    HandleLidSwitch=ignore
    HandleLidSwitchDocked=ignore
    HandleHibernateKey=ignore
  '';

  # Ensure the system does not automatically suspend or hibernate
  # This is an additional measure to above, can be adjusted as needed
  services.upower.enable = false;

  # Disable the GNOME3/GDM auto-suspend feature that cannot be disabled in GUI!
  # If no user is logged in, the machine will power down after 20 minutes.
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # The Jenkins slave service is very barebones
  # it only installs java and sets up jenkins user
  services.jenkinsSlave.enable = true;
}
