# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  self,
  inputs,
  pkgs,
  ...
}:
let
  # Vendored in, as brainstem isn't suitable for nixpkgs packaging upstream:
  # https://github.com/NixOS/nixpkgs/pull/313643
  brainstem = pkgs.callPackage ../../pkgs/brainstem { };

  jenkins-connection-script = pkgs.writeScript "jenkins-connect.sh" ''
    #!/usr/bin/env bash
    set -eu
    if [ ! -f agent.jar ]; then echo "Error: /var/lib/jenkins/agent.jar not found"; exit 1; fi;
    if [ ! -f secret-file ]; then echo "Error: /var/lib/jenkins/secret-file not found"; exit 1; fi;
    ${pkgs.jdk}/bin/java \
      -jar agent.jar \
      -jnlpUrl https://ghaf-jenkins-controller-dev.northeurope.cloudapp.azure.com/computer/testagent/jenkins-agent.jnlp \
      -secret @secret-file \
      -workDir "/var/lib/jenkins"
  '';
in
{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ]
    ++ (with inputs; [
      sops-nix.nixosModules.sops
      disko.nixosModules.disko
    ])
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

  networking = {
    hostName = "testagent";
    useNetworkd = true;
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  services.udev = {
    # Enable Acroname USB Smart switch, as well as LXA USB-SD-Mux support.
    packages = [
      brainstem
      pkgs.usbsdmux
    ];

    # udev rules for test devices serial connections
    extraRules = ''
      SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTD1BQQS", SYMLINK+="ttyORINNX1", MODE="0666", GROUP="dialout"
      SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTC0VRXR", SYMLINK+="ttyNUC1", MODE="0666", GROUP="dialout"
      SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea71", ATTRS{serial}=="0642246B630C149011EC987B167DB04", ENV{ID_USB_INTERFACE_NUM}=="01", SYMLINK+="ttyRISCV1", MODE="0666", GROUP="dialout"
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

  # Gives jenkins user sudo rights without password and serial connection rights
  users.users.jenkins.extraGroups = [
    "wheel"
    "dialout"
    "tty"
  ];

  # Open connection to Jenkins controller
  systemd.services.jenkins-connection = {
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
        wget
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

  # Details of the hardware devices connected to this host
  environment.etc."jenkins/test_config.json".text = builtins.toJSON {
    addresses = {
      NUC1 = {
        serial_port = "/dev/ttyNUC1";
        device_ip_address = "172.18.16.50";
        socket_ip_address = "172.18.16.30";
        plug_type = "TAPOP100v2";
        location = "testagent";
        usbhub_serial = "F0A0D6CF";
        threads = 8;
      };
      OrinAGX1 = {
        serial_port = "/dev/ttyACM0";
        device_ip_address = "172.18.16.36";
        socket_ip_address = "172.18.16.31";
        plug_type = "TAPOP100v2";
        location = "testagent";
        usbhub_serial = "92D8AEB7";
        threads = 8;
      };
      LenovoX1-2 = {
        serial_port = "NONE";
        device_ip_address = "172.18.16.66";
        socket_ip_address = "NONE";
        plug_type = "NONE";
        location = "testagent";
        usbhub_serial = "641B6D74";
        threads = 20;
      };
      Polarfire1 = {
        serial_port = "/dev/ttyRISCV1";
        device_ip_address = "";
        socket_ip_address = "172.18.16.45";
        plug_type = "TAPOP100v2";
        location = "testagent";
        usb_sd_mux_port = "/dev/sg1";
        threads = 4;
      };
      OrinNX1 = {
        serial_port = "/dev/ttyORINNX1";
        device_ip_address = "172.18.16.44";
        socket_ip_address = "172.18.16.43";
        plug_type = "TAPOP100v2";
        location = "testagent";
        usbhub_serial = "5220564F";
        threads = 8;
      };
    };
  };
}
