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
    ./hardware-configuration.nix
    ./disk-config.nix
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    user-bmg
    user-fayad
    team-devenv
  ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
  };

  users.groups.tsusers = { };

  # this server has been installed with 25.05
  system.stateVersion = lib.mkForce "25.05";

  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "uae-lab-node1";
    useDHCP = true;
    hosts = {
      "10.52.31.4" = [ "aks-uaenorth-dev-aic-profilence-730y5480.hcp.uaenorth.azmk8s.io" ];
    };
    nameservers = [
      "10.161.10.11"
      "10.161.10.12"
    ];
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
    dmidecode
    pciutils
    dnsutils
    inetutils
    wget
    openssl
    nix-info
    nebula
    kubectl
    helm
    argocd
    k9s
  ];

  services.fail2ban.enable = lib.mkForce false;
}
