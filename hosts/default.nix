# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
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
    common = import ./common.nix;
    generic-disk-config = import ./generic-disk-config.nix;
  };

  flake.nixosConfigurations = let
    # make self and inputs available in nixos modules
    specialArgs = {inherit self inputs;};
  in {
    # Currently not used for anything:
    # build01 = lib.nixosSystem {
    #   inherit specialArgs;
    #   modules = [./build01/configuration.nix];
    # };
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
  };
}
