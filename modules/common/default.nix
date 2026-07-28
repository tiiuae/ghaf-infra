# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  self,
  inputs,
  ...
}:

{
  imports = [
    self.nixosModules.service-monitoring
    inputs.sops-nix.nixosModules.sops
    ./nix-caches.nix
    ./nix.nix
  ];

  nix.caches = lib.mkDefault [
    "nixos-org"
    "ghaf-dev"
  ];

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 3;
  };

  boot.loader.timeout = 1;

  hardware.enableRedistributableFirmware = true;

  # Common network configuration
  networking.firewall.enable = true;
  networking.enableIPv6 = false;

  # Allow password-less sudo for wheel users
  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;

  # Contents of the user and group files will be replaced on system activation
  # Ref: https://search.nixos.org/options?channel=unstable&show=users.mutableUsers
  users.mutableUsers = false;

  # Set your time zone
  time.timeZone = "UTC";

  # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    wget
    curl
    vim
    git
    htop
    nix-info
  ];

  # Shell
  programs.bash.completion.enable = true;
}
