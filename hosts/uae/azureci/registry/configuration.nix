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
    ../../../registry.nix
    ../../azureci/azure-common.nix
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    service-nginx
    team-devenv
  ]);

  sops.defaultSopsFile = ./secrets.yaml;

  # this server has been initialized with 25.11 with nixos-anywhere
  system.stateVersion = lib.mkForce "25.11";

  hardware.enableRedistributableFirmware = true;
  networking.hostName = "uae-azureci-registry";

  # Use local filesystem storage until the AWS S3 me-central-1 outage is resolved.
  services.zot-registry = {
    clientId = "uae-zot-registry";
    domain = "registry.uaenorth.cloudapp.azure.com";
    metrics.enable = true;
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
