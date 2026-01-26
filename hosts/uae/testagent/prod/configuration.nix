# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  config,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ../../../testagent/agents-common.nix
  ]
  ++ (with self.nixosModules; [
    team-devenv
    team-testers
    user-flokli
  ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets.metrics_password.owner = "root";
  };
  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "uae-testagent-prod";
  services.testagent = {
    variant = "prod";
    hardware = [
      "lenovo-x1"
    ];
  };

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "nvme"
    "thunderbolt"
  ];
  boot.kernelModules = [
    "kvm-intel"
  ];

  # udev rules for test devices serial connections
  # placeholder configs from finland. need updation with new uae targets, in progress
  services.udev.extraRules = ''
    # Lenovo X1
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S7MLNS0X532696T", SYMLINK+="ssdX1", MODE="0666", GROUP="dialout"
  '';

  # Trigger UDEV rules
  system.activationScripts.udevTrigger = ''
    echo "==> Triggering udev rules..."
    /run/current-system/sw/bin/udevadm trigger --subsystem-match=tty
    /run/current-system/sw/bin/udevadm trigger --subsystem-match=block
  '';

  # disabled because there is not relay board configured
  systemd.services.relay-board-metric-exporter.enable = false;

  # Details of the hardware devices connected to this host
  # placeholder configs from finland. configs in progress based on new uae targets
  environment.etc."jenkins/test_config.json".text =
    let
      location = config.networking.hostName;
    in
    builtins.toJSON {
      addresses = {
        LenovoX1-1 = {
          inherit location;
          serial_port = "NONE";
          device_ip_address = "172.20.16.53";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "UAE-LenovoX1-prod";
          usbhub_serial = "B7D9AFB6";
          ext_drive_by-id = "/dev/ssdX1";
          threads = 20;
        };
        measurement_agent = {
          inherit location;
          device_ip_address = "172.18.16.10";
        };
      };
    };
}
