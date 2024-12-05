# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  inputs,
  lib,
  config,
  pkgs,
  ...
}:
let
  asGB = size: toString (size * 1024 * 1024 * 1024);
in
{
  nixpkgs.config.allowUnfree = true;

  nix = {
    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;
    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    settings = {
      # We can trust root and any users with sudo rights
      trusted-users = [
        "root"
        "@wheel"
      ];
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Subsituters
      trusted-public-keys = [
        "ghaf-dev.cachix.org-1:S3M8x3no8LFQPBfHw1jl6nmP8A7cVWKntoMKN3IsEQY="
        "prod-cache.vedenemo.dev~1:JcytRNMJJdYJVQCYwLNsrfVhct5dhCK2D3fa6O1WHOI="
      ];
      substituters = [
        "https://ghaf-dev.cachix.org?priority=20"
        "https://prod-cache.vedenemo.dev"
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
      # Fallback quickly if substituters are not available.
      connect-timeout = lib.mkDefault 5;
      # The default at 10 is rarely enough.
      log-lines = lib.mkDefault 25;
    };
    daemonCPUSchedPolicy = lib.mkDefault "batch";
    daemonIOSchedClass = lib.mkDefault "idle";
    daemonIOSchedPriority = lib.mkDefault 7;
  };

  # Make builds to be more likely killed than important services.
  # 100 is the default for user slices and 500 is systemd-coredumpd@
  # We rather want a build to be killed than our precious user sessions as builds can be easily restarted.
  systemd.services.nix-daemon.serviceConfig.OOMScoreAdjust = lib.mkDefault 250;

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
  programs.bash.completion.enable = true;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "23.11";
}
