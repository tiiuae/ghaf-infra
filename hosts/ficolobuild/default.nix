# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  ...
}: {
  flake.nixosConfigurations = {
    generic-x86_64-linux = lib.nixosSystem {
      specialArgs = {
        inherit self inputs;
      };
      modules = [
        inputs.disko.nixosModules.disko
        (with self.nixosModules; [
          user-cazfi
          user-hrosten
          user-jrautiola
          user-mkaapu
        ])
        ./configuration.nix
      ];
    };
  };
}
