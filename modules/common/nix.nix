# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  inputs,
  config,
  ...
}:
{
  # revision of the flake the configuration was built from.
  # $ nixos-version --configuration-revision
  system.configurationRevision = toString (
    self.rev or self.dirtyRev or self.lastModified or "unknown"
  );

  # commit time of the revision above, read by the drift metrics in modules/monitoring.nix
  environment.etc."configuration-revision-timestamp".text = "${toString (self.lastModified or 0)}\n";

  nixpkgs.config.allowUnfree = true;

  nix = {
    gc.automatic = lib.mkDefault true;

    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;
    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;
  };

  # Direct `switch` deployments across NixOS release boundaries can fail during
  # user-unit activation. Require a `boot` deployment followed by a reboot
  # instead of switching releases on a running system.
  system.switch.inhibitors.nixos-release = config.system.nixos.release;
}
