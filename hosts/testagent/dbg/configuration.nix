# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  config,
  ...
}:
{
  imports = [
    ../agents-common.nix
    ./disk-config.nix
  ];

  sops.defaultSopsFile = ./secrets.yaml;

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.11";
  networking.hostName = "testagent-dbg";
  services.testagent = {
    variant = "dbg";
    hardware = [ "orin-nx" ];
  };

  boot = {
    kernelModules = [
      "kvm-intel"
      "sg"
    ];
    initrd.availableKernelModules = [
      "xhci_pci"
      "thunderbolt"
      "ahci"
      "nvme"
      "uas"
      "usbhid"
      "sd_mod"
    ];
  };

  services.udev.extraRules = ''
    # Orin NX
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", ATTRS{serial}=="FTD0V63S", SYMLINK+="ttyORINNX1", MODE="0666", GROUP="dialout"
    # SSD-drive
    SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="S6WXNS0W300153T", SYMLINK+="ssdORINNX1", MODE="0666", GROUP="dialout"
  '';

  # No relay board is connected on this host.
  systemd.services.relay-board-metric-exporter.enable = false;

  environment.etc."jenkins/test_config.json".text =
    let
      location = config.networking.hostName;
    in
    builtins.toJSON {
      addresses = {
        relay_serial_port = "NONE";
        OrinNX1 = {
          inherit location;
          device_id = "00-28-62-e3-9e";
          netvm_hostname = "ghaf-0677569438";
          serial_port = "/dev/ttyORINNX1";
          relay_number = "NONE";
          device_ip_address = "172.18.16.30";
          socket_ip_address = "172.18.16.18";
          plug_type = "TAPOP100v2";
          switch_bot = "NONE";
          usbhub_serial = "92D8AEB7";
          ext_drive_by-id = "/dev/ssdORINNX1";
          threads = 8;
        };
      };
    };
}
