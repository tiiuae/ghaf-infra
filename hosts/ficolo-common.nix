# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ self, lib, ... }:
{
  imports = [ self.nixosModules.service-monitoring ];

  # Use ci-server as primary DNS and pfsense as secondary
  networking.nameservers = [
    "172.18.20.1"
  ];

  services.monitoring = {
    metrics.openFirewall = true;
    logs.lokiAddress = lib.mkDefault "http://172.18.20.108";
  };
}
