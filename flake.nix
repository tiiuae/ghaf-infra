# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  description = "NixOS configurations for Ghaf";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    # Secrets with sops-nix
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-stable.follows = "nixpkgs";
    };
    # Binary cache with nix-serve-ng
    nix-serve-ng = {
      url = github:aristanetworks/nix-serve-ng;
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Disko for disk partitioning
    disko = {
      url = github:nix-community/disko;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = {
    self,
    nixpkgs,
    disko,
    ...
  } @ inputs: let
    inherit (self) outputs;
    # Supported systems for your flake packages, shell, etc.
    systems = ["x86_64-linux"];
    # forEachSystem [ "x86_64-linux" ] { example = true; } -> { x86_64-linux.example = true }
    forEachSystem = nixpkgs.lib.genAttrs systems;
    # Imports a module expecting a system to be passed in
    importExpectingSystem = module: system:
      import module {
        pkgs = import nixpkgs {inherit system;};
      };
    ghaf-infra-shell = importExpectingSystem ./shell.nix;
    terraform-shell = importExpectingSystem ./terraform/shell.nix;
    templateTargets = import ./hosts/templates/targets.nix {inherit nixpkgs disko;};
  in {
    # nix fmt
    formatter = forEachSystem (system: nixpkgs.legacyPackages.${system}.alejandra);

    # Development shells
    devShells = forEachSystem (system: {
      # nix develop
      default = ghaf-infra-shell system;
      # nix develop .#terraform
      terraform = terraform-shell system;
    });

    # NixOS configuration entrypoint
    nixosConfigurations = {
      # Generic template configurations
      template-azure-x86_64-linux = templateTargets.azure-x86_64-linux;
      template-generic-x86_64-linux = templateTargets.generic-x86_64-linux;

      # Hydra host: ghafhydra
      ghafhydra = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        modules = [./hosts/ghafhydra/configuration.nix];
      };

      # Builder host: build01
      build01 = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        modules = [./hosts/build01/configuration.nix];
      };
    };
  };
}
