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
  # make self and inputs available in nixos modules
  specialArgs = {
    inherit self inputs;
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
    nixos-build3 = ./builders/build3/configuration.nix;
    nixos-build4 = ./builders/build4/configuration.nix;
    nixos-hetzarm = ./builders/hetzarm/configuration.nix;
    nixos-monitoring = ./monitoring/configuration.nix;
    nixos-himalia = ./himalia/configuration.nix;
    nixos-testagent-prod = ./testagent/prod/configuration.nix;
    nixos-testagent-dev = ./testagent/dev/configuration.nix;
    nixos-testagent-release = ./testagent/release/configuration.nix;
    nixos-ghaf-log = ./ghaf-log/configuration.nix;
    nixos-ghaf-coverity = ./ghaf-coverity/configuration.nix;
    nixos-ghaf-proxy = ./ghaf-proxy/configuration.nix;
    nixos-ghaf-webserver = ./ghaf-webserver/configuration.nix;
    nixos-testagent-uae-dev = ./testagent/uae-dev/configuration.nix;
  };

  # Expose as flake.lib.mkNixOS.
  flake.lib = {
    inherit mkNixOS;
  };

  # for each systemName, call mkNixOS on it, and set flake.nixosConfigurations
  # to an attrset from systemName to the result of that mkNixOS call.
  flake.nixosConfigurations = builtins.listToAttrs (
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
        "build3"
        "build4"
        "hetzarm"
        "monitoring"
        "himalia"
        "testagent-prod"
        "testagent-dev"
        "testagent-release"
        "ghaf-log"
        "ghaf-coverity"
        "ghaf-proxy"
        "ghaf-webserver"
        "testagent-uae-dev"
      ]
  );
}
