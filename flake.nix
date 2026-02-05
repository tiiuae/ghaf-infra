# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  description = "NixOS configurations for Ghaf Infra";

  nixConfig = {
    substituters = [
      "https://ghaf-dev.cachix.org"
      "https://cache.nixos.org/"
    ];
    extra-trusted-substituters = [
      "https://ghaf-dev.cachix.org"
      "https://cache.nixos.org/"
    ];
    extra-trusted-public-keys = [
      "ghaf-dev.cachix.org-1:S3M8x3no8LFQPBfHw1jl6nmP8A7cVWKntoMKN3IsEQY="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
  };

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    # Allows us to structure the flake with the NixOS module system
    flake-parts.url = "github:hercules-ci/flake-parts";

    flake-root.url = "github:srid/flake-root";
    flake-utils.url = "github:numtide/flake-utils";

    # Secrets with sops-nix
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Disko for disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # pre-commit hooks
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-compat.follows = "flake-compat";
      };
    };

    # For preserving compatibility with non-Flake users
    flake-compat = {
      url = "github:nix-community/flake-compat";
      flake = false;
    };

    # Used for deploying remote systems
    deploy-rs = {
      # pinned until this regression is fixed
      # https://github.com/serokell/deploy-rs/issues/325
      url = "github:serokell/deploy-rs/5829cec63845eb50984dc8787b0edfe81bf5b980";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-compat.follows = "flake-compat";
        utils.follows = "flake-utils";
      };
    };

    # Utilities used in the jenkins pipelines
    robot-framework = {
      url = "github:tiiuae/ci-test-automation";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    sbomnix = {
      url = "github:tiiuae/sbomnix";
      inputs = {
        flake-parts.follows = "flake-parts";
        flake-compat.follows = "flake-compat";
        flake-root.follows = "flake-root";
      };
    };

    ci-yubi = {
      url = "github:tiiuae/ci-yubi";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    # Installed into devshell
    nix-fast-build = {
      url = "github:Mic92/nix-fast-build";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
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
          ./scripts
        ];
      };
}
