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
    ../agents-common.nix
  ]
  ++ (with self.nixosModules; [
    team-devenv
    team-testers
    service-nebula
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
  networking.hostName = "uae-testagent-prod";
  services.testagent = {
    variant = "prod";
    hardware = [
      "lenovo-x1"
      "darter-pro"
    ];
  };

  nebula = {
    enable = true;
    cert = config.sops.secrets.nebula-cert.path;
    key = config.sops.secrets.nebula-key.path;
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
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="00000000NAAL2E2X", SYMLINK+="ssdX1", MODE="0666", GROUP="dialout"

    # Darter Pro
    # SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTFMF0X0", SYMLINK+="ttyDARTER", MODE="0666", GROUP="dialout"
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S7MNNL0YA16081M", SYMLINK+="ssdDARTER", MODE="0666", GROUP="dialout"
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
        relay_serial_port = "NONE";
        LenovoX1-1 = {
          inherit location;
          device_id = "00-87-26-3f-89";
          netvm_hostname = "ghaf-2267430793";
          serial_port = "NONE";
          device_ip_address = "172.20.16.53";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "UAE-LenovoX1-prod";
          usbhub_serial = "0xB7D9AFB6";
          ext_drive_by-id = "/dev/ssdX1";
          threads = 20;
        };
        DarterPRO = {
          inherit location;
          device_id = "00-e5-01-b6-aa";
          netvm_hostname = "ghaf-3842094762";
          serial_port = "/dev/ttyDARTER";
          device_ip_address = "172.20.16.54";
          socket_ip_address = "NONE";
          plug_type = "NONE";
          switch_bot = "UAE-DarterPRO-prod";
          usbhub_serial = "0x1674021B";
          ext_drive_by-id = "/dev/ssdDARTER";
          threads = 16;
        };
      };
    };
}
