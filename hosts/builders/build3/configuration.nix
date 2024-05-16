# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  config,
  ...
}: {
  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets.awsarm_ssh_key.owner = "root";

  imports =
    [
      ../ficolo.nix
      ../developers.nix
      ../yubikey.nix
      inputs.sops-nix.nixosModules.sops
    ]
    ++ (with self.nixosModules; [
      user-themisto
      user-ktu
      user-avnik
    ]);

  # build3 specific configuration

  networking.hostName = "build3";

  users.users.yubimaster.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMDfEUoARtE5ZMYofegtm3lECzaQeAktLQ2SqlHcV9jL signer"
  ];

  programs.ssh = {
    extraConfig = ''
      Host awsarm
        HostName awsarm.vedenemo.dev
        Port 20220
    '';
    knownHosts = {
      "[awsarm.vedenemo.dev]:20220".publicKey = "ssh-ed25519  AAAAC3NzaC1lZDI1NTE5AAAAIL3f7tAAO3Fc+8BqemsBQc/Yl/NmRfyhzr5SFOSKqrv0";
    };
  };

  nix = {
    settings = {
      # avoid copying stuff over ssh
      builders-use-substitutes = true;
      # add ability to build 32 bit
      extra-platforms = ["i686-linux"];
      trusted-users = ["root" "themisto" "@wheel" "build3"];
    };

    distributedBuilds = true;

    buildMachines = [
      {
        hostName = "awsarm";
        system = "aarch64-linux";
        maxJobs = 8;
        speedFactor = 1;
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
        mandatoryFeatures = [];
        sshUser = "build3";
        sshKey = config.sops.secrets.awsarm_ssh_key.path;
      }
    ];
  };
}
