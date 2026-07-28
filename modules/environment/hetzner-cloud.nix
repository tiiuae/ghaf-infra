# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  modulesPath,
  lib,
  machines,
  config,
  ...
}:
let
  defaultLoki = "http://${machines.ghaf-monitoring.internal_ip}:3100";
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  services.monitoring.logs.lokiAddress = lib.mkDefault defaultLoki;

  networking = {
    useDHCP = true;
    usePredictableInterfaceNames = false;
  };

  # disable firewall on hetzner internal network
  networking.firewall.trustedInterfaces = [ "eth1" ];

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
}
