# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
{
  # Ensure only the nixos.org and ghaf-release cachix cache are trusted
  nix.settings.trusted-public-keys = lib.mkForce [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "ghaf-release.cachix.org-1:wvnAftt8aSJ5KukTQb+BvvZYqJ5qzWEk/QHMbn2o+Ag="
  ];
  nix.settings.substituters = lib.mkForce [
    "https://cache.nixos.org/"
    "https://ghaf-release.cachix.org"
  ];
  nix.settings.extra-trusted-public-keys = lib.mkForce [ "" ];
  nix.settings.extra-substituters = lib.mkForce [ "" ];
  nix.settings.trusted-substituters = lib.mkForce [ "" ];
  nix.settings.trusted-users = [ "@wheel" ];
  services.openssh = {
    extraConfig = "TrustedUserCAKeys /etc/ssh/keys/ssh_user_ca.pub";
  };
}
