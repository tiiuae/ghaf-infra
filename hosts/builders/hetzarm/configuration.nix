# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  ...
}: {
  sops.defaultSopsFile = ./secrets.yaml;

  imports =
    [
      ./disk-config.nix
      ../developers.nix
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
      service-node-exporter
      user-cazfi
      user-hrosten
      user-jrautiola
      user-mkaapu
      user-tervis
      user-karim
      user-mika
      user-themisto
    ]);

  # Set authorized keys for sshified user
  users.users.sshified = {
    isNormalUser = true;
    group = "sshified";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEKd30t0EFmMyULGlecaUX6puIAF4IjynZUo+X9k8h69 monitoring"
    ];
  };
  users.groups.sshified = {};
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "hetzarm";
    useDHCP = true;
  };

  boot = {
    initrd.availableKernelModules = ["nvme" "usbhid"];
    # use predictable network interface names (eth0)
    kernelParams = ["net.ifnames=0"];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  nix.settings.trusted-users = ["themisto" "@wheel"];
}
