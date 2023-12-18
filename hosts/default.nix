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
    ficolo-hosts = import ./ficolo-hosts.nix;
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
    binary-cache = lib.nixosSystem {
      inherit specialArgs;
      modules = [./binary-cache/configuration.nix];
    };
    builder = lib.nixosSystem {
      inherit specialArgs;
      modules = [./builder/configuration.nix];
    };
    ficolobuild = lib.nixosSystem {
      inherit specialArgs;
      modules = [./ficolobuild/configuration.nix];
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
