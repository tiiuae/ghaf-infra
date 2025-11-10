# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  self,
  config,
  ...
}:
{
  imports =
    [
      ../agents-common.nix
      ./hardware-configuration.nix
    ]
    ++ (with self.nixosModules; [
      service-nebula
      team-devenv
      team-testers
      user-flokli
    ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      metrics_password.owner = "alloy";
      nebula-cert.owner = config.nebula.user;
      nebula-key.owner = config.nebula.user;
    };
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "testagent-prod";
  services.testagent = {
    variant = "prod";
    hardware = [
      "lenovo-x1"
      "dell-7330"
      "darter-pro"
    ];
  };

  nebula = {
    enable = true;
    cert = config.sops.secrets.nebula-cert.path;
    key = config.sops.secrets.nebula-key.path;
  };

  # udev rules for test devices serial connections
  services.udev.extraRules = ''
    # Lenovo X1
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S7MLNS0X532696T", SYMLINK+="ssdX1", MODE="0666", GROUP="dialout"

    # Dell 7330
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="50026B72836E78E0", SYMLINK+="ssdDELL7330", MODE="0666", GROUP="dialout"

    # Darter Pro
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="50026B72838C556F", SYMLINK+="ssdDARTER", MODE="0666", GROUP="dialout"

  '';

  # Trigger UDEV rules
  system.activationScripts.udevTrigger = ''
    echo "==> Triggering udev rules..."
    /run/current-system/sw/bin/udevadm trigger --subsystem-match=tty
    /run/current-system/sw/bin/udevadm trigger --subsystem-match=block
  '';

  # Details of the hardware devices connected to this host
  environment.etc."jenkins/test_config.json".text =
    let
      location = config.networking.hostName;
    in
    builtins.toJSON {
      addresses = {
        relay_serial_port = "NONE";
        LenovoX1-1 = {
          inherit location;
          serial_port = "NONE";
          device_ip_address = "172.18.16.66";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "LenovoX1-prod";
          usbhub_serial = "641B6D74";
          ext_drive_by-id = "/dev/ssdX1";
          threads = 20;
        };
        Dell7330 = {
          inherit location;
          serial_port = "NONE";
          device_ip_address = "172.18.16.7";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "Dell7330-prod";
          usbhub_serial = "FF62140D";
          ext_drive_by-id = "/dev/ssdDELL7330";
          threads = 8;
        };
        DarterPRO = {
          inherit location;
          serial_port = "NONE";
          device_ip_address = "172.18.16.21";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "DarterPRO-prod";
          usbhub_serial = "2CA3D5CC";
          ext_drive_by-id = "/dev/ssdDARTER";
          threads = 16;
        };
        measurement_agent = {
          inherit location;
          device_ip_address = "172.18.16.10";
        };
      };
    };
}
