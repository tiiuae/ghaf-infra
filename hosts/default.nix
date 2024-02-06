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
    qemu-common = import ./qemu-common.nix;
    ficolo-common = import ./ficolo-common.nix;
    common = import ./common.nix;
    generic-disk-config = import ./generic-disk-config.nix;
  };

  flake.nixosConfigurations = let
    # make self and inputs available in nixos modules
    specialArgs = {inherit self inputs;};
  in {
    binarycache = lib.nixosSystem {
      inherit specialArgs;
      modules = [./binarycache/configuration.nix];
    };
    binary-cache = lib.nixosSystem {
      inherit specialArgs;
      modules = [./binary-cache/configuration.nix];
    };
    builder = lib.nixosSystem {
      inherit specialArgs;
      modules = [./builder/configuration.nix];
    };
    ficolobuild3 = lib.nixosSystem {
      inherit specialArgs;
      modules = [./ficolobuild/build3.nix];
    };
    ficolobuild4 = lib.nixosSystem {
      inherit specialArgs;
      modules = [./ficolobuild/build4.nix];
    };
    jenkins-controller = lib.nixosSystem {
      inherit specialArgs;
      modules = [./jenkins-controller/configuration.nix];
    };
    prbuilder = lib.nixosSystem {
      inherit specialArgs;
      modules = [./prbuilder/configuration.nix];
    };
    monitoring = lib.nixosSystem {
      inherit specialArgs;
      modules = [./monitoring/configuration.nix];
    };
  };
}
