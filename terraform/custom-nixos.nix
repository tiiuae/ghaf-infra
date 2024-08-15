# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: MIT
# Nix trampoline calling the flake, and instantiating a
# flake.nixosModules.nixos-${systemName} as a NixOS system,
# then returning the Azure Image for it.
# It allows passing in extraNixPublicKeys and extraNixSubstituters via --argstr.
{
  system ? builtins.currentSystem,
  # The name of the system.
  # Needs a flake.nixosModules.nixos-${systemName}" to exist.
  # FUTUREWORK: construct attrset for all flake.nixosModules.nixos-*,
  # so we can just use foobar.config.system.build.azureImage as attrpath
  systemName,
  # Additional nix binary cache public keys
  extraNixPublicKey ? "",
  # Additional nix substituters
  extraNixSubstituter ? "",
}:
let
  flake = import ../. { inherit system; };
  inherit (flake.inputs.nixpkgs) lib;

  out = flake.lib.mkNixOS {
    inherit systemName;
    extraConfig = {
      nix.settings.trusted-public-keys = lib.optional (extraNixPublicKey != "") extraNixPublicKey;
      nix.settings.substituters = lib.optional (extraNixSubstituter != "") extraNixSubstituter;
    };
  };
in
out.config.system.build.azureImage
