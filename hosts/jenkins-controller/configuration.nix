# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  ...
}: {
  imports = [
    ../azure-common-2.nix
    self.nixosModules.service-openssh
  ];

  # Configure /var/lib/jenkins in /etc/fstab.
  # Due to an implicit RequiresMountsFor=$state-dir, systemd
  # will block starting the service until this mounted.
  fileSystems."/var/lib/jenkins" = {
    device = "/dev/disk/by-lun/10";
    fsType = "ext4";
    options = [
      # Due to https://github.com/hashicorp/terraform-provider-azurerm/issues/6117
      # disks get attached later during boot.
      # The default of 90s doesn't seem to be sufficient.
      "x-systemd.device-timeout=5min"
      "x-systemd.makefs"
      "x-systemd.growfs"
    ];
  };

  services.jenkins = {
    enable = true;
    listenAddress = "localhost";
    port = 8080;
    withCLI = true;
  };

  # set StateDirectory=jenkins, so state volume has the right permissions
  # and we wait on the mountpoint to appear.
  # https://github.com/NixOS/nixpkgs/pull/272679
  systemd.services.jenkins.serviceConfig.StateDirectory = "jenkins";

  # TODO: deploy reverse proxy, sort out authentication (SSO?)

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  system.stateVersion = "23.05";
}
