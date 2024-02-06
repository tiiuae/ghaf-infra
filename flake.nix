# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  description = "NixOS configurations for Ghaf";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/master";
    # Allows us to structure the flake with the NixOS module system
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-root.url = "github:srid/flake-root";
    # Secrets with sops-nix
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-stable.follows = "nixpkgs";
    };
    # Binary cache with nix-serve-ng
    nix-serve-ng = {
      url = "github:aristanetworks/nix-serve-ng";
      # Broken with 23.11, base32 misses text >=2.0 && <2.1
      # inputs.nixpkgs.follows = "nixpkgs";
    };
    # Disko for disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Format all the things
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # For preserving compatibility with non-Flake users
    flake-compat = {
      url = "github:nix-community/flake-compat";
      flake = false;
    };
  };

  outputs = inputs @ {
    flake-parts,
    nixpkgs,
    ...
  }:
    flake-parts.lib.mkFlake
    {
      inherit inputs;
      specialArgs = {
        inherit (nixpkgs) lib;
      };
    } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [
        ./hosts
        ./nix
        ./services
        ./users
      ];
    };
}
