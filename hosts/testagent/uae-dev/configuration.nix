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
      ./disk-config.nix
      ../agents-common.nix
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
  networking.hostName = "testagent-uae-dev";
  services.testagent = {
    variant = "dev";
    hardware = [
      "orin-agx"
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
    # Orin agx
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S6XNNS0W202677W", SYMLINK+="ssdORINAGX1", MODE="0666", GROUP="dialout"

    # Lenovo X1
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S6XPNS0W606188E", SYMLINK+="ssdX1", MODE="0666", GROUP="dialout"
  '';

  # Trigger UDEV rules
  system.activationScripts.udevTrigger = ''
    echo "==> Triggering udev rules..."
    /run/current-system/sw/bin/udevadm trigger --subsystem-match=tty
    /run/current-system/sw/bin/udevadm trigger --subsystem-match=block
  '';

  # Details of the hardware devices connected to this host
  # placeholder configs from finland. configs in progress based on new uae targets
  environment.etc."jenkins/test_config.json".text =
    let
      location = config.networking.hostName;
    in
    builtins.toJSON {
      addresses = {
        OrinAGX1 = {
          inherit location;
          serial_port = "/dev/ttyACM0";
          device_ip_address = "172.19.16.13";
          socket_ip_address = "172.19.16.23";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usbhub_serial = "0x2954223B";
          ext_drive_by-id = "/dev/ssdORINAGX1";
          threads = 8;
        };
        LenovoX1-1 = {
          inherit location;
          serial_port = "NONE";
          device_ip_address = "172.19.16.14";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "LenovoX1-uae-dev";
          usbhub_serial = "0x99EB9D84";
          ext_drive_by-id = "/dev/ssdX1";
          threads = 20;
        };
      };
    };
}
