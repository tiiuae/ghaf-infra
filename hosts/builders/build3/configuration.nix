# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  config,
  ...
}:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets.ssh_private_key.owner = "root";

  imports =
    [
      ../ficolo.nix
      ../cross-compilation.nix
      ../developers.nix
      ../yubikey.nix
      ../builders-common.nix
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
    "hetzarm.vedenemo.dev".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILx4zU4gIkTY/1oKEOkf9gTJChdx/jR3lDgZ7p/c7LEK";
  };
}
