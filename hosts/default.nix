# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  self,
  inputs,
  lib,
  ...
}:
let
  hostInventory = import ./machines.nix;
  machines = lib.mapAttrs (_: host: host.machine) (
    lib.filterAttrs (_: host: host ? machine) hostInventory
  );
  isAutoConfiguredHost = _: host: (host.kind or "host") != "vm";

  # make self and inputs available in nixos modules
  specialArgs = {
    inherit self inputs machines;
  };

  # Calls nixosSystem with a toplevel config
  # (needs to be a "nixos-"-prefixed module in `self.nixosModules`),
  # and optional extra configuration.
  mkNixOS =
    {
      systemName,
      extraConfig ? null,
    }:
    lib.nixosSystem {
      inherit specialArgs;
      modules = [
        self.nixosModules."nixos-${systemName}"
        {
          nixpkgs.hostPlatform = hostInventory.${systemName}.system;
        }
      ]
      ++ lib.optional (extraConfig != null) extraConfig;
    };

  mkHetzciVm =
    {
      mountHostNixStore ? true,
    }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit specialArgs;
      modules = [
        (import ./vm-nixos-qemu.nix {
          disk_gb = 200;
          vcpus = 4;
          ram_gb = 20;
          mount_host_nix_store = mountHostNixStore;
        })
        self.nixosModules.nixos-hetzci-vm
        {
          nixpkgs.hostPlatform = hostInventory.hetzci-vm.system;
          # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/qemu-vm.nix
          virtualisation.vmVariant.virtualisation.forwardPorts = [
            {
              from = "host";
              host.port = 8080;
              guest.port = 80;
            }
            {
              from = "host";
              host.port = 2222;
              guest.port = 22;
            }
          ];
        }
      ];
    };

  nixosModulesFromHosts = lib.mapAttrs' (
    name: host: lib.nameValuePair "nixos-${name}" host.module
  ) hostInventory;

  nixosConfigurationsFromHosts = builtins.mapAttrs (name: _host: mkNixOS { systemName = name; }) (
    lib.filterAttrs isAutoConfiguredHost hostInventory
  );
in
{
  flake.nixosModules = {
    # shared modules
    common = import ./common.nix;
  }
  // nixosModulesFromHosts;

  # Expose as flake.lib.mkNixOS.
  flake.lib = {
    inherit mkNixOS;
  };

  flake.nixosConfigurations = nixosConfigurationsFromHosts // {
    hetzci-vm = mkHetzciVm { };
    hetzci-vm-no-host-nix-store = mkHetzciVm {
      mountHostNixStore = false;
    };
  };
}
