# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, ... }:
{
  networking.firewall = {
    allowedTCPPorts = [ config.services.prometheus.exporters.node.port ];
    allowedUDPPorts = [ config.services.prometheus.exporters.node.port ];
  };

  services.prometheus.exporters = {
    node = {
      enable = true;
      enabledCollectors = [ "systemd" ];
      port = 9100;
    };
  };
}
