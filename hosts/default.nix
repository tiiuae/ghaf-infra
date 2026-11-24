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

  # Per-system grouping of the inventory's host names, driven by its `system`
  # field. hetzci-vm-no-host-nix-store has no inventory entry: its toplevel is
  # the same as hetzci-vm's.
  hostsBySystem = lib.foldlAttrs (
    acc: name: host:
    acc // { ${host.system} = (acc.${host.system} or [ ]) ++ [ name ]; }
  ) { } hostInventory;

  # make self and inputs available in nixos modules
  specialArgs = {
    inherit self inputs machines;
  };

  pkgsBySystem = lib.mapAttrs (
    system: _:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    }
  ) hostsBySystem;

  # Calls nixosSystem with a host configuration module from the inventory and
  # optional extra configuration.
  mkNixOS =
    {
      systemName,
      extraConfig ? null,
    }:
    lib.nixosSystem {
      inherit specialArgs;
      modules = [
        hostInventory.${systemName}.module
        (
          { pkgs, ... }:
          {
            nixpkgs.hostPlatform = hostInventory.${systemName}.system;
            nixpkgs.pkgs = lib.mkDefault pkgsBySystem.${hostInventory.${systemName}.system};
            boot.kernelPackages = pkgs.linuxPackages_latest;
          }
        )
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
        hostInventory.hetzci-vm.module
        (
          { pkgs, ... }:
          {
            nixpkgs.hostPlatform = hostInventory.hetzci-vm.system;
            nixpkgs.pkgs = lib.mkDefault pkgsBySystem.${hostInventory.hetzci-vm.system};
            boot.kernelPackages = pkgs.linuxPackages_latest;
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
        )
      ];
    };

  nixosConfigurationsFromHosts = builtins.mapAttrs (name: _host: mkNixOS { systemName = name; }) (
    lib.filterAttrs isAutoConfiguredHost hostInventory
  );
in
{
  flake.lib = {
    inherit mkNixOS hostsBySystem;
  };

  flake.nixosConfigurations = nixosConfigurationsFromHosts // {
    hetzci-vm = mkHetzciVm { };
    hetzci-vm-no-host-nix-store = mkHetzciVm {
      mountHostNixStore = false;
    };
  };
}
