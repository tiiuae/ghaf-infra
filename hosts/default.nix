# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
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
      ] ++ lib.optional (extraConfig != null) extraConfig;
    };
in
{
  flake.nixosModules = {
    # shared modules
    qemu-common = import ./qemu-common.nix;
    ficolo-common = import ./ficolo-common.nix;
    common = import ./common.nix;
    generic-disk-config = import ./generic-disk-config.nix;

    # All flake.nixosConfigurations, before we call lib.nixosSystem over them.
    # We use a 'nixos-' prefix to distinguish them from regular modules.
    #
    # These are available to allow extending system configuration with
    # out-of-tree additional config (like additional trusted cache public keys)
    nixos-az-binary-cache = ./azure/binary-cache/configuration.nix;
    nixos-az-builder = ./azure/builder/configuration.nix;
    nixos-az-jenkins-controller = ./azure/jenkins-controller/configuration.nix;
    nixos-binarycache = ./binarycache/configuration.nix;
    nixos-build1 = ./builders/build1/configuration.nix;
    nixos-build2 = ./builders/build2/configuration.nix;
    nixos-build3 = ./builders/build3/configuration.nix;
    nixos-build4 = ./builders/build4/configuration.nix;
    nixos-hetzarm = ./builders/hetzarm/configuration.nix;
    nixos-monitoring = ./monitoring/configuration.nix;
    nixos-testagent-prod = ./testagent/prod/configuration.nix;
    nixos-testagent-dev = ./testagent/dev/configuration.nix;
    nixos-testagent-release = ./testagent/release/configuration.nix;
    nixos-nethsm-gateway = ./nethsm-gateway/configuration.nix;
    nixos-ghaf-log = ./ghaf-log/configuration.nix;
    nixos-ghaf-proxy = ./ghaf-proxy/configuration.nix;
    nixos-ghaf-webserver = ./ghaf-webserver/configuration.nix;
    nixos-ghaf-auth = ./ghaf-auth/configuration.nix;
    nixos-ghaf-monitoring = ./ghaf-monitoring/configuration.nix;
    nixos-ghaf-lighthouse = ./ghaf-lighthouse/configuration.nix;
    nixos-testagent-uae-dev = ./testagent/uae-dev/configuration.nix;
    nixos-hetzci-dev = ./hetzci/dev/configuration.nix;
    nixos-hetzci-prod = ./hetzci/prod/configuration.nix;
    nixos-hetzci-release = ./hetzci/release/configuration.nix;
    nixos-hetzci-vm = ./hetzci/vm/configuration.nix;
    nixos-hetz86-1 = ./builders/hetz86-1/configuration.nix;
    nixos-hetz86-builder = ./builders/hetz86-builder/configuration.nix;
    nixos-hetz86-rel-1 = ./builders/hetz86-rel-1/configuration.nix;
  };

  # Expose as flake.lib.mkNixOS.
  flake.lib = {
    inherit mkNixOS;
  };

  # for each systemName, call mkNixOS on it, and set flake.nixosConfigurations
  # to an attrset from systemName to the result of that mkNixOS call.
  flake.nixosConfigurations =
    (builtins.listToAttrs (
      builtins.map
        (name: {
          inherit name;
          value = mkNixOS { systemName = name; };
        })
        [
          "az-binary-cache"
          "az-builder"
          "az-jenkins-controller"
          "binarycache"
          "build1"
          "build2"
          "build3"
          "build4"
          "hetzarm"
          "monitoring"
          "testagent-prod"
          "testagent-dev"
          "testagent-release"
          "nethsm-gateway"
          "ghaf-log"
          "ghaf-proxy"
          "ghaf-webserver"
          "ghaf-auth"
          "ghaf-monitoring"
          "ghaf-lighthouse"
          "testagent-uae-dev"
          "hetzci-dev"
          "hetzci-prod"
          "hetzci-release"
          "hetz86-1"
          "hetz86-builder"
          "hetz86-rel-1"
        ]
    ))
    // {
      hetzci-vm = inputs.nixpkgs.lib.nixosSystem {
        inherit specialArgs;
        modules = [
          (import ./vm-nixos-qemu.nix {
            disk_gb = 200;
            vcpus = 4;
            ram_gb = 20;
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
    };
}
