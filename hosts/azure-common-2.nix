# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
#
# Profile to import for Azure VMs. Imports azure-common.nix from nixpkgs,
# and configures cloud-init.
{
  modulesPath,
  pkgs,
  ...
}: {
  imports = [
    "${modulesPath}/virtualisation/azure-config.nix"
  ];

  nix = {
    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Subsituters
      trusted-public-keys = [
        "ghaf-dev.cachix.org-1:S3M8x3no8LFQPBfHw1jl6nmP8A7cVWKntoMKN3IsEQY="
        "cache.vedenemo.dev:8NhplARANhClUSWJyLVk4WMyy1Wb4rhmWW2u8AejH9E="
      ];
      substituters = [
        "https://ghaf-dev.cachix.org?priority=20"
        "https://cache.vedenemo.dev"
      ];
    };
  };

  # enable cloud-init, so instance metadata is set accordingly and we can use
  # cloud-config for ssh key management.
  services.cloud-init.enable = true;

  # Use systemd-networkd for network configuration.
  services.cloud-init.network.enable = true;
  networking.useDHCP = false;
  networking.useNetworkd = true;
  # FUTUREWORK: Ideally, we'd keep systemd-resolved disabled too,
  # but the way nixpkgs configures cloud-init prevents it from picking up DNS
  # settings from elsewhere.
  # services.resolved.enable = false;

  # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    git
    vim
    htop
  ];
}
