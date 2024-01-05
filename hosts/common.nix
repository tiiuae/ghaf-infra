# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: let
  asGB = size: toString (size * 1024 * 1024 * 1024);
in {
  nixpkgs.config.allowUnfree = true;

  nix = {
    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: {flake = value;}) inputs;
    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Subsituters
      trusted-public-keys = [
        "ghaf-dev.cachix.org-1:S3M8x3no8LFQPBfHw1jl6nmP8A7cVWKntoMKN3IsEQY="
        "cache.vedenemo.dev:8NhplARANhClUSWJyLVk4WMyy1Wb4rhmWW2u8AejH9E="
        "cache.ssrcdevops.tii.ae:oOrzj9iCppf+me5/3sN/BxEkp5SaFkHfKTPPZ97xXQk="
      ];
      substituters = [
        "https://ghaf-dev.cachix.org?priority=20"
        "https://cache.vedenemo.dev"
        "https://cache.ssrcdevops.tii.ae"
      ];
      # Avoid copying unecessary stuff over SSH
      builders-use-substitutes = true;
      # Auto-free the /nix/store:
      #
      # Ref:
      # https://nixos.wiki/wiki/Storage_optimization#Automation
      # https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-min-free
      #
      # When free disk space in /nix/store drops below min-free during build,
      # perform a garbage-collection until max-free bytes are available or there
      # is no more garbage.
      min-free = asGB 20;
      max-free = asGB 200;
      # check the free disk space every 5 seconds
      min-free-check-interval = 5;
    };
    # Garbage collection
    gc.automatic = true;
    gc.options = pkgs.lib.mkDefault "--delete-older-than 7d";
  };

  # Sometimes it fails if a store path is still in use.
  # This should fix intermediate issues.
  systemd.services.nix-gc.serviceConfig = {
    Restart = "on-failure";
  };

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
  programs.bash.enableCompletion = true;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "23.11";
}
