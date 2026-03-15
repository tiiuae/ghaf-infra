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
  machines = import ./machines.nix;

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
          nixpkgs.hostPlatform = "x86_64-linux";
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

  # All host module paths in one place.
  # Most hosts can be instantiated with mkNixOS; hetzci-vm is created by mkHetzciVm.
  hostModules = {
    hetzarm = ./builders/hetzarm/configuration.nix;
    hetzarm-dbg-1 = ./builders/hetzarm-dbg-1/configuration.nix;
    hetzarm-rel-1 = ./builders/hetzarm-rel-1/configuration.nix;
    testagent-prod = ./testagent/prod/configuration.nix;
    testagent-dev = ./testagent/dev/configuration.nix;
    testagent2-prod = ./testagent/prod2/configuration.nix;
    testagent-release = ./testagent/release/configuration.nix;
    nethsm-gateway = ./nethsm-gateway/configuration.nix;
    ghaf-log = ./ghaf-log/configuration.nix;
    ghaf-webserver = ./ghaf-webserver/configuration.nix;
    ghaf-auth = ./ghaf-auth/configuration.nix;
    ghaf-monitoring = ./ghaf-monitoring/configuration.nix;
    ghaf-lighthouse = ./ghaf-lighthouse/configuration.nix;
    ghaf-fleetdm = ./ghaf-fleetdm/configuration.nix;
    ghaf-registry = ./ghaf-registry/configuration.nix;
    hetzci-dbg = ./hetzci/dbg/configuration.nix;
    hetzci-dev = ./hetzci/dev/configuration.nix;
    hetzci-prod = ./hetzci/prod/configuration.nix;
    hetzci-release = ./hetzci/release/configuration.nix;
    hetzci-vm = ./hetzci/vm/configuration.nix;
    hetz86-1 = ./builders/hetz86-1/configuration.nix;
    hetz86-builder = ./builders/hetz86-builder/configuration.nix;
    hetz86-dbg-1 = ./builders/hetz86-dbg-1/configuration.nix;
    hetz86-rel-2 = ./builders/hetz86-rel-2/configuration.nix;
    uae-lab-node1 = ./uae/lab/node1/configuration.nix;
    uae-nethsm-gateway = ./uae/nethsm-gateway/configuration.nix;
    uae-azureci-prod = ./uae/azureci/prod/configuration.nix;
    uae-azureci-az86-1 = ./uae/azureci/builders/az86-1/configuration.nix;
    uae-testagent-prod = ./uae/testagent/prod/configuration.nix;
    uae-azureci-hetzarm-1 = ./uae/azureci/builders/hetzarm-1/configuration.nix;
  };

  nixosModulesFromHosts = lib.mapAttrs' (
    name: path: lib.nameValuePair "nixos-${name}" path
  ) hostModules;

  nixosConfigurationsFromHosts = builtins.mapAttrs (name: _path: mkNixOS { systemName = name; }) (
    lib.removeAttrs hostModules [ "hetzci-vm" ]
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
