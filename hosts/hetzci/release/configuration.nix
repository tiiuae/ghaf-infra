# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
{
  imports = [
    ./disk-config.nix
    ../common.nix
    ../jenkins.nix
    ../remote-builders.nix
    ../cloud.nix
    ../auth.nix
  ];

  system.stateVersion = lib.mkForce "25.05";
  networking.hostName = "hetzci-release";
  sops.defaultSopsFile = ./secrets.yaml;

  hetzci = {
    jenkins = {
      casc = ./casc;
      pluginsFile = ./plugins.json;
    };
    auth = {
      clientID = "hetzci-release";
      domain = "ci-release.vedenemo.dev";
    };
  };

  nebula.enable = false;

  # Configure /var/lib/caddy in /etc/fstab.
  fileSystems."/var/lib/caddy" = {
    device = "/dev/disk/by-id/scsi-0HC_Volume_103219547";
    fsType = "ext4";
    options = [
      "x-systemd.makefs"
      "x-systemd.growfs"
    ];
  };
}
