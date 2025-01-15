# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Profile to import for Azure VMs. Imports azure-common.nix from nixpkgs,
# and configures cloud-init.
{ modulesPath, pkgs, ... }:
let
  asGB = size: toString (size * 1024 * 1024 * 1024);
in
{
  imports = [ "${modulesPath}/virtualisation/azure-config.nix" ];

  nix = {
    settings = {
      # Enable flakes and 'nix' command
      experimental-features = "nix-command flakes";
      # When free disk space in /nix/store drops below min-free during build,
      # perform a garbage-collection until max-free bytes are available or there
      # is no more garbage.
      min-free = asGB 20;
      max-free = asGB 200;
      # check the free disk space every 5 seconds
      min-free-check-interval = 5;
      # Trust users in the wheel group. They can sudo anyways.
      trusted-users = [ "@wheel" ];
    };
  };
  systemd.services.nix-gc.serviceConfig = {
    Restart = "on-failure";
  };

  # Enable azure agent
  virtualisation.azure.agent.enable = true;

  # enable cloud-init, so instance metadata is set accordingly and we can use
  # cloud-config for ssh key management.
  services.cloud-init.enable = true;
  # FUTUREWORK: below is a hack to make cloud-init usable with azure
  # agent (waagent). The usage of azure agent together with cloud-init
  # needs to be properly done later, perhaps by using the
  # azure-scatch-store-common.nix or something similar.
  systemd.services.cloud-config.serviceConfig = {
    Restart = "on-failure";
  };

  # Use systemd-networkd for network configuration.
  services.cloud-init.network.enable = true;
  networking.useDHCP = false;
  networking.useNetworkd = true;
  # FUTUREWORK: Ideally, we'd keep systemd-resolved disabled too,
  # but the way nixpkgs configures cloud-init prevents it from picking up DNS
  # settings from elsewhere.
  # services.resolved.enable = false;

  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;

  # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    tree
  ];
}
