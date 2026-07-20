# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ../developers.nix
    ../builders-common.nix
    ../cross-compilation.nix
    ../cachix-push.nix
    ../../hetzner-robot.nix
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    team-devenv
    user-github
    user-remote-build
  ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      cachix-auth-token.owner = "root";
    };
  };

  networking.hostName = "hetz86-1";
  boot.kernelModules = [ "kvm-amd" ];

  # Current host sizing: 96 vCPU, 251 GiB RAM, ~1760 GiB /nix disk.
  builder.tuning = {
    enable = true;
    cpus = 96;
    ramGiB = 251;
    diskGiB = 1760;
  };

  cachix-push = {
    cacheName = "ghaf-dev";
  };

  services.monitoring = {
    metrics = {
      enable = true;
      ssh = true;
    };
    logs.enable = true;
  };

}
