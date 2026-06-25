# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ ... }:
{
  imports = [
    ./disk-config.nix
    ../common.nix
  ];

  sops.defaultSopsFile = ./secrets.yaml;

  system.stateVersion = "25.11";

  networking.hostName = "nethsm-gateway-dev";

  # NetHSM connected directly to the ethernet port
  networking.interfaces.enp89s0 = {
    ipv4.addresses = [
      {
        address = "10.255.255.3";
        prefixLength = 30;
      }
    ];
  };
}
