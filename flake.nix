# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  description = "NixOS configurations for Ghaf";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    # Allows us to structure the flake with the NixOS module system
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-root.url = "github:srid/flake-root";
    # Secrets with sops-nix
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-stable.follows = "nixpkgs";
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
    # Used for deploying remote systems
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # pipeline dependencies
    robot-framework = {
      url = "github:tiiuae/ci-test-automation";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sbomnix = {
      url = "github:tiiuae/sbomnix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ci-yubi = {
      url = "github:tiiuae/ci-yubi";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-fast-build = {
      url = "github:Mic92/nix-fast-build";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
        treefmt-nix.follows = "treefmt-nix";
      };
    };
  };

  outputs =
    inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake
      {
        inherit inputs;
        specialArgs = {
          inherit (nixpkgs) lib;
        };
      }
      {
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
