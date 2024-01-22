# SPDX-FileCopyrightText: 2023-2024 Technology Innovation Institute (TII)
# SPDX-License-Identifier: Apache-2.0
#
{
  self,
  inputs,
  lib,
  ...
}: {
  flake.nixosModules = {
    # shared modules
    azure-common = import ./azure-common.nix;
    qemu-common = import ./qemu-common.nix;
    ficolo-common = import ./ficolo-common.nix;
    common = import ./common.nix;
    generic-disk-config = import ./generic-disk-config.nix;
  };

  flake.nixosConfigurations = let
    # make self and inputs available in nixos modules
    specialArgs = {inherit self inputs;};
  in {
    ghafhydra = lib.nixosSystem {
      inherit specialArgs;
      modules = [./ghafhydra/configuration.nix];
    };
    binarycache = lib.nixosSystem {
      inherit specialArgs;
      modules = [./binarycache/configuration.nix];
    };
    monitoring = lib.nixosSystem {
      inherit specialArgs;
      modules = [./monitoring/configuration.nix];
    };
    ficolobuild3 = lib.nixosSystem {
      inherit specialArgs;
      modules = [./ficolobuild/build3.nix];
    };
    prbuilder = lib.nixosSystem {
      inherit specialArgs;
      modules = [./prbuilder/configuration.nix];
    };
  };
}
