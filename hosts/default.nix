# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  ...
}: {
  flake.nixosModules = {
    # shared modules
    azure-common = import ./azure-common.nix;
    qemu-common = import ./qemu-common.nix;
    common = import ./common.nix;
    generic-disk-config = import ./generic-disk-config.nix;
  };

  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: {
    nixosConfigurations = let
      # make self and inputs available in nixos modules
      specialArgs = {inherit self inputs;};
    in
      lib.mkIf (system == "x86_64-linux") {
        ghafhydra = lib.nixosSystem {
          inherit pkgs specialArgs;
          modules = [./ghafhydra/configuration.nix];
        };
        binarycache = lib.nixosSystem {
          inherit pkgs specialArgs;
          modules = [./binarycache/configuration.nix];
        };
        monitoring = lib.nixosSystem {
          inherit pkgs specialArgs;
          modules = [./monitoring/configuration.nix];
        };
        ficolobuild = lib.nixosSystem {
          inherit pkgs specialArgs;
          modules = [./ficolobuild/configuration.nix];
        };
      };
  };
}
