# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  pkgs,
  inputs,
  lib,
  self,
  ...
}:
let
  # Vendored in, as brainstem isn't suitable for nixpkgs packaging upstream:
  # https://github.com/NixOS/nixpkgs/pull/313643
  brainstem = pkgs.callPackage ../../pkgs/brainstem { };
in
{
  imports =
    [
      ./agent.nix
      inputs.sops-nix.nixosModules.sops
      inputs.disko.nixosModules.disko
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
    ]);

  sops.secrets =
    let
      credential = {
        sopsFile = ./credentials.yaml;
        owner = "jenkins";
      };
    in
    {
      dut-pass = credential;
      plug-login = credential;
      plug-pass = credential;
      switch-token = credential;
      switch-secret = credential;
      wifi-ssid = credential;
      wifi-password = credential;
      pi-login = credential;
      pi-pass = credential;
    };

  networking.useDHCP = true;

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;
  };

  services.udev.packages = [
    brainstem
    pkgs.usbsdmux
  ];

  # packages available in all user sessions
  environment.systemPackages =
    [
      brainstem
      inputs.robot-framework.packages.${pkgs.system}.ghaf-robot
    ]
    ++ (with pkgs; [
      minicom
      usbsdmux
      grafana-loki
      (python3.withPackages (ps: with ps; [ pyserial ]))
    ]);

  # This server is only exposed to the internal network
  # fail2ban only causes issues here
  services.fail2ban.enable = lib.mkForce false;
}
