# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  ...
}: {
  services = {
    harmonia = {
      enable = true;
      signKeyPath = config.sops.secrets.cache-sig-key.path;
      package = pkgs.harmonia.overrideAttrs (old: {
        patches =
          old.patches
          or []
          ++ [
            # Cherry-pick of https://github.com/nix-community/harmonia/pull/293 into 0.7.3
            # We can't bump to 0.7.5 in release-23.11 as it brings a libnixstore bump
            # with backwards-incompatible changes (for a new Nix version).
            # Sent upstream in https://github.com/NixOS/nixpkgs/pull/297989,
            # can be dropped here once nixpkgs channel moves past that.
            (pkgs.fetchpatch {
              url = "https://github.com/nix-community/harmonia/pull/293/commits/3232511db91b7dce97172a8b018f0056585890f5.patch";
              hash = "sha256-BQ2eJkPTKnwa62dqy6qe7Jq+wJ2Ds5VhT5ST/xVlHiQ=";
            })
          ];
      });
    };
  };
  networking.firewall.allowedTCPPorts = [5000];
}
