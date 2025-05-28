# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
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

  # build4 specific configuration

  disko.devices.disk = {
    sda.device = "/dev/disk/by-id/ata-DELLBOSS_VD_0c174cf02ac90010";
    sdb.device = "/dev/disk/by-id/scsi-362cea7f07374e80027870010d6eab515";
    root.device = "/dev/disk/by-id/nvme-Dell_Ent_NVMe_AGN_MU_U.2_1.6TB_S61ENE0N801253";
    home.device = "/dev/disk/by-id/nvme-Dell_Ent_NVMe_AGN_MU_U.2_1.6TB_S61ENE0N801251";
  };

  sops.defaultSopsFile = ./secrets.yaml;

  networking.hostName = "build4";
}
