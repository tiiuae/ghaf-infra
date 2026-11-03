# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  modulesPath,
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.virtualisation.hetzner;
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  options.virtualisation.hetzner.withEfiSupport = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether the cloud server boots using UEFI rather than legacy BIOS.";
  };

  config = {
    networking = {
      useDHCP = true;
      usePredictableInterfaceNames = false;
      firewall.trustedInterfaces = [ "eth1" ];
    };

    boot.loader = {
      systemd-boot.enable = cfg.withEfiSupport;
      grub = lib.mkIf (!cfg.withEfiSupport) {
        enable = true;
        configurationLimit = 3;
      };
    };

    environment.systemPackages = lib.optionals cfg.withEfiSupport [ pkgs.efibootmgr ];
  };
}
