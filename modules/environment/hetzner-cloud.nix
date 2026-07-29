# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  modulesPath,
  lib,
  machines,
  config,
  pkgs,
  ...
}:
let
  defaultLoki = "http://${machines.ghaf-monitoring.internal_ip}:3100";
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
    services.monitoring.logs.lokiAddress = lib.mkDefault defaultLoki;

    networking = {
      useDHCP = true;
      usePredictableInterfaceNames = false;
    };

    # disable firewall on hetzner internal network
    networking.firewall.trustedInterfaces = [ "eth1" ];

    boot.loader = {
      systemd-boot.enable = cfg.withEfiSupport;
      grub = lib.mkIf (!cfg.withEfiSupport) {
        enable = true;
        configurationLimit = 3;
      };
    };

    environment.systemPackages = lib.optionals cfg.withEfiSupport [ pkgs.efibootmgr ];

    warnings = [
      (lib.mkIf
        (
          config.services.monitoring.logs.enable
          && (config.services.monitoring.logs.lokiAddress == defaultLoki)
          # naively assume name in machines matches hostname for now
          && (!builtins.hasAttr "internal_ip" machines.${config.networking.hostName})
        )
        "${config.networking.hostName} sends logs to hetzner internal network but has no internal ip defined! is it part of the network?"
      )
    ];
  };
}
