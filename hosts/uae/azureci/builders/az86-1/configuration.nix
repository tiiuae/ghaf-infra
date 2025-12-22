# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  inputs,
  modulesPath,
  lib,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ../../azure-common.nix
    ../../../../builders/developers.nix
    ../../../../builders/builders-common.nix
    ../../../../builders/cross-compilation.nix
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    team-devenv
    user-github
  ]);

  users.users = {
    remote-build = {
      description = "User for remote builds";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG23fArR5mkx9eCHVKZ2EN/fqxR5LcXKkz4e8DSwLwG+"
      ];
      extraGroups = [ ];
    };
  };

  nix.settings.trusted-users = [
    "@wheel"
    "remote-build"
  ];

  sops.defaultSopsFile = ./secrets.yaml;

  # this server has been initialized with 25.05 with nixos-anywhere
  # initializing fails with 24.11
  system.stateVersion = lib.mkForce "25.05";

  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "uae-azureci-az86-1";
  };

  boot = {
    # use predictable network interface names (eth0)
    kernelParams = [ "net.ifnames=0" ];
    loader.grub = {
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
  };

  environment.systemPackages = with pkgs; [
    screen
    tmux
    cryptsetup
    sg3_utils
    dnsutils
    inetutils
    pciutils
    dmidecode
    jq
  ];
}
