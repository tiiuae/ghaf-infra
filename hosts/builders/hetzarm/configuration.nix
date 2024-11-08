# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  ...
}:
{
  sops.defaultSopsFile = ./secrets.yaml;

  imports =
    [
      ./disk-config.nix
      ../developers.nix
      ../builders-common.nix
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
      service-monitoring
      user-cazfi
      user-hrosten
      user-jrautiola
      user-mkaapu
      user-karim
      user-mika
      user-github
      user-remote-build
    ]);

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "hetzarm";
    useDHCP = true;
  };

  services.monitoring.metrics.enable = true;

  boot = {
    initrd.availableKernelModules = [
      "nvme"
      "usbhid"
    ];
    # use predictable network interface names (eth0)
    kernelParams = [ "net.ifnames=0" ];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  users.users = {
    # sshified user for monitoring server to log in as
    sshified = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEKd30t0EFmMyULGlecaUX6puIAF4IjynZUo+X9k8h69 monitoring"
      ];
    };

    # build3 can use this as remote builder
    build3 = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPf56a3ISY64w0Y0BmoLu+RyTIWQrXG6ugla6if9RteT build3"
      ];
    };
  };

  nix.settings.trusted-users = [
    "@wheel"
    "build3"
  ];
}
