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
      controllerUrl = "https://ghaf-jenkins-controller-villepekkajuntun.northeurope.cloudapp.azure.com";
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
              -name "${device}" \
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
      user-maarit
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

  services.udev = {
    # Enable Acroname USB Smart switch, as well as LXA USB-SD-Mux support.
    packages = [
      brainstem
      pkgs.usbsdmux
    ];

    # udev rules for test devices serial connections
    extraRules = ''
      SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTD0W9KS", SYMLINK+="ttyORINNX1", MODE="0666", GROUP="dialout"
      SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTD0WF8Y", SYMLINK+="ttyNUC1", MODE="0666", GROUP="dialout"
      SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea71", ATTRS{serial}=="04A629B8AB87AB8111ECB2A38815028", ENV{ID_USB_INTERFACE_NUM}=="01", SYMLINK+="ttyRISCV1", MODE="0666", GROUP="dialout"
    '';
  };

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
    agent-riscv = mkAgent "riscv";
    agent-nuc = mkAgent "nuc";
    agent-lenovo-x1 = mkAgent "lenovo-x1";
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
          switch_bot = "NONE";
          usbhub_serial = "0x2954223B";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6XNNS0W202677W-0:0";
          threads = 8;
        };
        OrinNX1 = {
          inherit location;
          serial_port = "/dev/ttyORINNX1";
          device_ip_address = "172.18.16.61";
          socket_ip_address = "172.18.16.95";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usbhub_serial = "0xEE92E4FD";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6XPNS0W606359P-0:0";
          threads = 8;
        };
        Polarfire1 = {
          inherit location;
          serial_port = "/dev/ttyRISCV1";
          device_ip_address = "NONE";
          socket_ip_address = "172.18.16.82";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usb_sd_mux_port = "/dev/sg1";
          ext_drive_by-id = "usb-LinuxAut_sdmux_HS-SD_MMC_000000001267-0:0";
          threads = 4;
        };
        NUC1 = {
          inherit location;
          serial_port = "/dev/ttyNUC1";
          device_ip_address = "172.18.16.16";
          socket_ip_address = "172.18.16.20";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usbhub_serial = "0x029CEAF3";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6XNNS0W201129V-0:0";
          threads = 8;
        };
        LenovoX1-1 = {
          inherit location;
          serial_port = "NONE";
          device_ip_address = "172.18.16.17";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "LenovoX1-dev";
          usbhub_serial = "0x99EB9D84";
          ext_drive_by-id = "usb-Samsung_PSSD_T7_S6XPNS0W606188E-0:0";
          threads = 20;
        };
      };
    };
}
