# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  pkgs,
  config,
  ...
}:
let
  # Vendored in, as brainstem isn't suitable for nixpkgs packaging upstream:
  # https://github.com/NixOS/nixpkgs/pull/313643
  brainstem = pkgs.callPackage ../../pkgs/brainstem { };

  mkAgent =
    device:
    let
      # Temporary url for development
      controllerUrl = "https://ghaf-jenkins-controller-joonasrautiola.northeurope.cloudapp.azure.com";
      workDir = "/var/lib/jenkins/agents/${device}";

      jenkins-connection-script =
        pkgs.writeScript "jenkins-connect.sh" # sh
          ''
            #!/usr/bin/env bash
            set -eu

            mkdir -p "${workDir}"

            # get agent.jar
            if [ ! -f agent.jar ]; then
              wget "${controllerUrl}/jnlpJars/agent.jar"
            fi

            # TODO: get secret from jenkins api here, right now it's manual process
            if [ ! -f "secret_${device}" ]; then echo "Error: /var/lib/jenkins/secret_${device} not found"; exit 1; fi;

            ${pkgs.jdk}/bin/java \
              -jar agent.jar \
              -url "${controllerUrl}" \
              -name "testagent_${device}" \
              -secret "@secret_${device}" \
              -workDir "${workDir}" \
              -webSocket
          '';
    in
    {
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      # Give up if it fails more than 5 times in 60 second interval
      startLimitBurst = 5;
      startLimitIntervalSec = 60;

      path =
        [
          brainstem
          inputs.robot-framework.packages.${pkgs.system}.ghaf-robot
        ]
        ++ (with pkgs; [
          wget
          jdk
          git
          bashInteractive
          coreutils
          util-linux
          nix
          zstd
          jq
          csvkit
          sudo
          openssh
          iputils
          netcat
          python3
          usbsdmux
        ]);

      serviceConfig = {
        Type = "simple";
        User = "jenkins";
        WorkingDirectory = "/var/lib/jenkins";
        ExecStart = "${jenkins-connection-script}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
in
{
  imports =
    [
      ./disk-config.nix
      inputs.sops-nix.nixosModules.sops
      inputs.disko.nixosModules.disko
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
      user-vjuntunen
      user-flokli
      user-jrautiola
      user-mariia
      user-hrosten
    ]);

  sops.defaultSopsFile = ./secrets.yaml;
  nixpkgs.hostPlatform = "x86_64-linux";

  networking = {
    hostName = "testagent-dev";
    useDHCP = true;
  };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    initrd.availableKernelModules = [
      "vmd"
      "xhci_pci"
      "ahci"
      "nvme"
      "usbhid"
      "usb_storage"
      "sd_mod"
      "sr_mod"
      "rtsx_pci_sdmmc"
    ];
    kernelModules = [
      "kvm-intel"
      "sg"
    ];
  };

  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;
  };

  # Enable Acroname USB Smart switch, as well as LXA USB-SD-Mux support.
  services.udev.packages = [
    brainstem
    pkgs.usbsdmux
  ];

  environment.systemPackages =
    [
      inputs.robot-framework.packages.${pkgs.system}.ghaf-robot
      brainstem
    ]
    ++ (with pkgs; [
      minicom
      usbsdmux
    ]);

  # The Jenkins slave service is very barebones
  # it only installs java and sets up jenkins user
  services.jenkinsSlave.enable = true;

  # Jenkins needs sudo and serial rights to perform the HW tests
  users.users.jenkins.extraGroups = [
    "wheel"
    "dialout"
    "tty"
  ];

  # Agent services per hardware test device
  systemd.services = {
    agent-orin-agx = mkAgent "orin-agx";
    agent-orin-nx = mkAgent "orin-nx";
  };

  # Details of the hardware devices connected to this host
  environment.etc."jenkins/test_config.json".text =
    let
      location = config.networking.hostName;
    in
    builtins.toJSON {
      addresses = {
        OrinAGX1 = {
          inherit location;
          serial_port = "/dev/ttyACM0";
          device_ip_address = "172.18.16.54";
          socket_ip_address = "172.18.16.74";
          plug_type = "TAPOP100v2";
          usbhub_serial = "0x2954223B";
          threads = 8;
        };
        OrinNX1 = {
          inherit location;
          serial_port = "/dev/ttyUSB0";
          device_ip_address = "172.18.16.61";
          socket_ip_address = "172.18.16.95";
          plug_type = "TAPOP100v2";
          usbhub_serial = "0xEE92E4FD";
          threads = 8;
        };
      };
    };
}
