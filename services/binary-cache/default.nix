# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, ... }:
{
  services = {
    harmonia = {
      enable = true;
      signKeyPaths = [ config.sops.secrets.cache-sig-key.path ];
    };
  };
  networking.firewall.allowedTCPPorts = [ 5000 ];
}
