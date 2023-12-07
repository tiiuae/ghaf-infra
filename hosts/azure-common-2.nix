# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
#
# Profile to import for Azure VMs. Imports azure-common.nix from nixpkgs,
# and configures cloud-init.
{
  modulesPath,
  pkgs,
  ...
}: {
  imports = [
    "${modulesPath}/virtualisation/azure-config.nix"
  ];

  nixpkgs.overlays = [
    (_self: super: {
      cloud-init = super.cloud-init.overrideAttrs (old: {
        patches =
          old.patches
          or []
          ++ [
            # Add support for timeout in disk_setup: https://github.com/canonical/cloud-init/pull/4673
            (pkgs.fetchpatch {
              url = "https://github.com/canonical/cloud-init/pull/4673/commits/9b2e3dc907dc06d0a2abdaae6f0b1f0612c5c5dc.patch";
              hash = "sha256-KAd+4YT+dgzIoEq5qZj6y4peclIb3rvnuY6QIQObAiY=";
            })
          ];
      });
    })
  ];

  # enable cloud-init, so instance metadata is set accordingly and we can use
  # cloud-config for ssh key management.
  services.cloud-init.enable = true;

  # Use systemd-networkd for network configuration.
  services.cloud-init.network.enable = true;
  networking.useDHCP = false;
  networking.useNetworkd = true;
  # FUTUREWORK: Ideally, we'd keep systemd-resolved disabled too,
  # but the way nixpkgs configures cloud-init prevents it from picking up DNS
  # settings from elsewhere.
  # services.resolved.enable = false;

  # Add filesystem-related tools to cloud-inits path, so it can format data disks.
  services.cloud-init.btrfs.enable = true;
  services.cloud-init.ext4.enable = true;
  services.cloud-init.xfs.enable = true;
}
