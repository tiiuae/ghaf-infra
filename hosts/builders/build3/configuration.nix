# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  config,
  ...
}:
{
  imports =
    [
      ../ficolo.nix
      ../cross-compilation.nix
      ../developers.nix
      ../builders-common.nix
      inputs.sops-nix.nixosModules.sops
    ]
    ++ (with self.nixosModules; [
      service-openssh
      team-devenv
      user-bmg
      user-avnik
      user-github # Remove when all GhA workflows moved to build4
      user-remote-build # Remove when all jenkins builds moved to build4
    ]);

  disko.devices.disk = {
    sda.device = "/dev/disk/by-id/ata-DELLBOSS_VD_22781d60fbbe0010";
    sdb.device = "/dev/disk/by-id/scsi-362cea7f07374850027870046da90a1b0";
    root.device = "/dev/disk/by-id/nvme-Dell_Ent_NVMe_AGN_MU_U.2_1.6TB_S61ENE0N801247";
    home.device = "/dev/disk/by-id/nvme-Dell_Ent_NVMe_AGN_MU_U.2_1.6TB_S61ENE0N801257";
  };

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets.ssh_private_key.owner = "root";
  };

  networking.hostName = "build3";

  nix.settings.trusted-users = [ "@wheel" ];

  # use hetzarm as aarch64 remote builder
  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "hetzarm.vedenemo.dev";
        system = "aarch64-linux";
        maxJobs = 40;
        speedFactor = 1;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
        mandatoryFeatures = [ ];
        sshUser = "build3";
        sshKey = config.sops.secrets.ssh_private_key.path;
      }
    ];
  };

  programs.ssh.knownHosts = {
    "hetzarm.vedenemo.dev".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILx4zU4gIkTY/1oKEOkf9gTJChdx/jR3lDgZ7p/c7LEK";
  };
}
