# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ config, lib, ... }:
{
  sops.secrets.metrics_password.owner = "alloy";

  networking.useDHCP = true;

  boot.loader.efi.canTouchEfiVariables = true;

  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;
  };

  # This server is only exposed to the internal network. Fail2ban only causes
  # issues here.
  services.fail2ban.enable = lib.mkForce false;

  system.activationScripts.udevTrigger = ''
    echo "==> Triggering udev rules..."
    /run/current-system/sw/bin/udevadm trigger --subsystem-match=tty
    /run/current-system/sw/bin/udevadm trigger --subsystem-match=block
  '';

  services.monitoring = {
    metrics.enable = true;
    logs = {
      enable = true;
      lokiAddress = "https://monitoring.vedenemo.dev";
      auth.password_file = config.sops.secrets.metrics_password.path;
    };
  };

  nix.gc = {
    automatic = true;
    dates = "daily";
    randomizedDelaySec = "45min";
    persistent = false;
    options = "--delete-older-than 14d";
  };
}
