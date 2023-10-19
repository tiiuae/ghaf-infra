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
    ...
  } @ inputs: let
    inherit (self) outputs;
    # Supported systems for your flake packages, shell, etc.
    systems = [
      "x86_64-linux"
    ];
    forEachSystem = f: nixpkgs.lib.genAttrs systems (system: f pkgsFor.${system});
    pkgsFor = nixpkgs.lib.genAttrs systems (system:
      import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      });
    bootstrapTargets = import ./bootstrap/targets.nix {inherit nixpkgs inputs outputs;};
  in {
    # Formatter for the nix files, available through 'nix fmt'
    formatter = forEachSystem (pkgs: pkgs.alejandra);
    # Development shell, available through 'nix develop'
    devShells = forEachSystem (pkgs: import ./shell.nix {inherit pkgs;});
    # NixOS configuration entrypoint
    nixosConfigurations = {
      # Generic bootstrap configurations
      bootstrap-azure-x86_64-linux = bootstrapTargets.azure-x86_64-linux;
      bootstrap-generic-x86_64-linux = bootstrapTargets.generic-x86_64-linux;

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
