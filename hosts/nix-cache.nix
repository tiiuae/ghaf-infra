# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Declarative binary cache configuration. Each host specifies which caches
# it needs by name.
#
# Usage:
#   ghaf.nix-cache.caches = [ "nixos-org" ];
#   ghaf.nix-cache.caches = [ "nixos-org" "ghaf-release" ];
#   ghaf.nix-cache.caches = [ "nixos-org" "ghaf-dev" ];
#   ghaf.nix-cache.caches = [ "nixos-org" "ghaf-dbg" ];
{ config, lib, ... }:
let
  cfg = config.ghaf.nix-cache;

  knownCaches = {
    nixos-org = {
      url = "https://cache.nixos.org/";
      publicKey = "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=";
    };
    ghaf-dev = {
      url = "https://ghaf-dev.cachix.org";
      publicKey = "ghaf-dev.cachix.org-1:S3M8x3no8LFQPBfHw1jl6nmP8A7cVWKntoMKN3IsEQY=";
    };
    ghaf-dbg = {
      url = "https://ghaf-dbg.cachix.org";
      publicKey = "ghaf-dbg.cachix.org-1:LkJhY5JBeZ/lV33t2sih+93j202ojMQ4lOVXcSV4LXE=";
    };
    ghaf-release = {
      url = "https://ghaf-release.cachix.org";
      publicKey = "ghaf-release.cachix.org-1:wvnAftt8aSJ5KukTQb+BvvZYqJ5qzWEk/QHMbn2o+Ag=";
    };
  };

  selectedCaches = map (name: knownCaches.${name}) cfg.caches;
in
{
  options.ghaf.nix-cache.caches = lib.mkOption {
    type = lib.types.nonEmptyListOf (lib.types.enum (builtins.attrNames knownCaches));
    description = "Binary caches to use.";
  };

  config.nix.settings = {
    trusted-public-keys = map (c: c.publicKey) selectedCaches;
    substituters = map (c: c.url) selectedCaches;
  };
}
