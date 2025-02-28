# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  inputs,
  modulesPath,
  lib,
  config,
  ...
}:
{
  imports =
    [
      ./disk-config.nix
      (modulesPath + "/profiles/qemu-guest.nix")
      inputs.sops-nix.nixosModules.sops
      inputs.disko.nixosModules.disko
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
      service-monitoring
      user-jrautiola
      user-fayad
      user-cazfi
      user-bmg
      user-flokli
      user-hrosten
      user-ktu
      user-vjuntunen
      user-alextserepov
    ]);

  # this server has been installed with 24.05
  system.stateVersion = lib.mkForce "24.05";

  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.enableRedistributableFirmware = true;

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      loki_password.owner = "promtail";
    };
  };

  services.monitoring = {
    metrics = {
      enable = true;
      ssh = true;
    };
    logs = {
      enable = true;
      lokiAddress = "https://monitoring.vedenemo.dev";
      auth.password_file = config.sops.secrets.loki_password.path;
    };
  };

  networking = {
    hostName = "ghaf-proxy";
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

  environment.systemPackages = with pkgs; [
    screen
    tmux
  ];
}
