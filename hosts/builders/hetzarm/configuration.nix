# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  config,
  ...
}:
{
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
      user-github
      user-remote-build
    ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      loki_password.owner = "promtail";
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "hetzarm";
    useDHCP = true;
  };

  services.monitoring = {
    metrics = {
      enable = true;
      ssh = true;
    };
    logs = {
      enable = true;
      lokiAddress = "https://monitoring.vedenemo.dev";
      auth.password_file = config.sops.secrets.loki_password.path;
    };
  };

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

  # build3 can use this as remote builder
  users.users.build3 = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPf56a3ISY64w0Y0BmoLu+RyTIWQrXG6ugla6if9RteT build3"
    ];
  };

  nix.settings.trusted-users = [
    "@wheel"
    "build3"
  ];
}
