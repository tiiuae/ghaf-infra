# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Profile to import for Azure VMs. Imports azure-common.nix from nixpkgs,
# and configures cloud-init.
{
  self,
  pkgs,
  ...
}:

let
  asGB = size: toString (size * 1024 * 1024 * 1024);
in
{
  imports = [
    self.nixosModules.azure
  ];

  config = {
    nix = {
      settings = {
        # Enable flakes and 'nix' command
        experimental-features = "nix-command flakes";
        # https://github.com/NixOS/nix/issues/11728
        download-buffer-size = 524288000;
        # When free disk space in /nix/store drops below min-free during build,
        # perform a garbage-collection until max-free bytes are available or there
        # is no more garbage.
        min-free = asGB 20;
        max-free = asGB 200;
        # check the free disk space every 5 seconds
        min-free-check-interval = 5;
        # Trust users in the wheel group. They can sudo anyways.
        trusted-users = [ "@wheel" ];
      };
    };
    systemd.services.nix-gc.serviceConfig = {
      Restart = "on-failure";
    };

    environment.systemPackages = with pkgs; [
      efibootmgr
    ];

    hardware.enableRedistributableFirmware = true;

    security.sudo.enable = true;
    security.sudo.wheelNeedsPassword = false;
  };
}
