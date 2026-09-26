# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ ... }:
{
  nix.caches = [
    "nixos-org"
    "ghaf-release"
  ];
  nix.settings.trusted-users = [ "@wheel" ];
  services.openssh = {
    extraConfig = "TrustedUserCAKeys /var/lib/baseline-reset/release-builder-ca.pub";
  };
}
