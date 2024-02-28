# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
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
    az-binary-cache = lib.nixosSystem {
      inherit specialArgs;
      modules = [./azure/binary-cache/configuration.nix];
    };
    az-builder = lib.nixosSystem {
      inherit specialArgs;
      modules = [./azure/builder/configuration.nix];
    };
    az-jenkins-controller = lib.nixosSystem {
      inherit specialArgs;
      modules = [./azure/jenkins-controller/configuration.nix];
    };
    binarycache = lib.nixosSystem {
      inherit specialArgs;
      modules = [./binarycache/configuration.nix];
    };
    ficolobuild3 = lib.nixosSystem {
      inherit specialArgs;
      modules = [./ficolobuild/build3.nix];
    };
    ficolobuild4 = lib.nixosSystem {
      inherit specialArgs;
      modules = [./ficolobuild/build4.nix];
    };
    monitoring = lib.nixosSystem {
      inherit specialArgs;
      modules = [./monitoring/configuration.nix];
    };
    prbuilder = lib.nixosSystem {
      inherit specialArgs;
      modules = [./prbuilder/configuration.nix];
    };
  };
}
