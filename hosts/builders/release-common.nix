# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ ... }:
{
  ghaf.nix-cache.caches = [
    "nixos-org"
    "ghaf-release"
  ];
  nix.settings.trusted-users = [ "@wheel" ];
  services.openssh = {
    extraConfig = "TrustedUserCAKeys /etc/ssh/keys/ssh_user_ca.pub";
  };
}
