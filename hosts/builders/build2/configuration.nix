# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  ...
}:
{
  imports =
    [
      ../ficolo.nix
      ../cross-compilation.nix
      ../builders-common.nix
      inputs.sops-nix.nixosModules.sops
    ]
    ++ (with self.nixosModules; [
      service-openssh
      team-devenv
      user-github
      user-remote-build
    ]);

  # build2 specific configuration

  disko.devices.disk = {
    sda.device = "/dev/disk/by-id/scsi-362cea7f0737489002786fe0bbde781c4";
    sdb.device = "/dev/disk/by-id/ata-DELLBOSS_VD_9c8a18dee7d80010";
    root.device = "/dev/disk/by-id/nvme-Dell_Ent_NVMe_AGN_MU_U.2_1.6TB_S61ENE0N801254";
    home.device = "/dev/disk/by-id/nvme-Dell_Ent_NVMe_AGN_MU_U.2_1.6TB_S61ENE0N801252";
  };

  sops.defaultSopsFile = ./secrets.yaml;

  networking.hostName = "build2";
}
