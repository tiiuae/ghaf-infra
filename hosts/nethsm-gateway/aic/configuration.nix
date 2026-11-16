# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ../common.nix
  ];

  sops.defaultSopsFile = ./secrets.yaml;

  system.stateVersion = "25.11";
  networking.hostName = "nethsm-gateway-aic";

  # NetHSM connected directly to the ethernet port
  networking.interfaces.enp0s20f0u2 = {
    ipv4.addresses = [
      {
        address = "10.255.255.3";
        prefixLength = 29;
      }
    ];
  };

  # temporary overrides for local manual lab use
  pkcs11.proxy.listenAddr = "0.0.0.0";
  networking.firewall.allowedTCPPorts = [ config.pkcs11.proxy.listenPort ];
  systemd.services.pkcs11-daemon.environment.PKCS11_PROXY_TLS_PSK_FILE =
    lib.mkForce "/etc/pkcs11/tls-psk";
  # make way for manual config file
  sops.templates."p11nethsm.conf".path = lib.mkForce "/etc/nitrokey/p11nethsm-nix.conf";
  nebula.enable = false;
}
