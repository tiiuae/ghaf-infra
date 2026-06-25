# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  lib,
  config,
  ...
}:
{
  imports = [
    ./disk-config.nix
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
    ./nethsm.nix
  ]
  ++ (with self.nixosModules; [
    common
    team-devenv
    service-openssh
    service-monitoring
    service-nebula
  ]);

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      loki_password.owner = "alloy";
    };
  };

  system.stateVersion = "25.11";

  networking.hostName = "nethsm-gateway-dev";
  networking.useDHCP = true;

  # NetHSM connected directly to the ethernet port
  networking.interfaces.enp89s0 = {
    ipv4.addresses = [
      {
        address = "10.255.255.3";
        prefixLength = 30;
      }
    ];
  };

  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;
  };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    kernelModules = [ "kvm-intel" ];
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

  nethsm.host = "10.255.255.1";

  services.monitoring = {
    metrics.enable = true;
    logs = {
      enable = true;
      lokiAddress = "https://monitoring.vedenemo.dev";
      auth.password_file = config.sops.secrets.loki_password.path;
    };

    alloy.configFiles.nethsm = # hcl
      ''
        local.file_match "nethsm" {
        	path_targets = [{
        		__address__ = "localhost",
        		__path__ = "${config.nethsm.logging.file}",
        		host = "${config.networking.hostName}",
        		job = "nethsm-log",
        	}]
        }

        loki.source.file "nethsm" {
        	targets = local.file_match.nethsm.targets
        	forward_to = [loki.write.default.receiver]
        }
      '';
  };

  # This server is only exposed to the internal network
  # fail2ban only causes issues here
  services.fail2ban.enable = lib.mkForce false;
}
