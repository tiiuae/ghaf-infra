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
let
  tuning = import ../../../../lib/nix-tuning.nix { inherit lib; };

  # Current host sizing: 32 vCPU, 128 GiB RAM.
  build = tuning.mkBuildLimits {
    cpus = 32;
    ramGiB = 128;
  };
in
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
    user-uae-remote-build
  ]);

  sops.defaultSopsFile = ./secrets.yaml;

  # this server has been initialized with 25.05 with nixos-anywhere
  # initializing fails with 24.11
  system.stateVersion = lib.mkForce "25.05";

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

  nix.settings.max-jobs = lib.mkForce build.maxJobs;
  nix.settings.cores = lib.mkForce build.cores;
}
