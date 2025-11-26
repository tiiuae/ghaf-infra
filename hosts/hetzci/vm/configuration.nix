# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, pkgs, ... }:
{
  imports = [
    ./disk-config.nix
    ../common.nix
    ../jenkins.nix
    ../remote-builders.nix
    ../signing.nix
  ];

  system.stateVersion = lib.mkForce "25.05";
  networking.hostName = "hetzci-vm";
  sops.defaultSopsFile = ./secrets.yaml;

  hetzci.jenkins = {
    envType = "vm";
    casc = ./casc;
    pluginsFile = ./plugins.json;
  };

  # VM specific configuration:
  virtualisation.vmVariant = {
    virtualisation.sharedDirectories.shr = {
      source = "$HOME/.config/vmshared/hetzci-vm";
      target = "/shared";
    };
  };

  # Stub Caddy config for vm
  services.caddy = {
    enable = true;
    enableReload = false;
    configFile = pkgs.writeText "Caddyfile" ''
      {
        admin off
        debug
        auto_https off
      }

      http://localhost, http://127.0.0.1 {

        # Route /artifacts requests to caddy file_server
        handle_path /artifacts* {
          root * /var/lib/jenkins/artifacts
          file_server {
            browse
          }
        }

        handle {
          reverse_proxy localhost:8081
        }
      }
    '';
  };
}
