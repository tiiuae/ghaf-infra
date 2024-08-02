# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  modulesPath,
  lib,
  config,
  ...
}: {
  sops.defaultSopsFile = ./secrets.yaml;

  imports =
    [
      ./disk-config.nix
      (modulesPath + "/profiles/qemu-guest.nix")
      inputs.sops-nix.nixosModules.sops
      inputs.disko.nixosModules.disko
      ./loki.nix
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
      service-nginx
      service-node-exporter
      user-jrautiola
      user-cazfi
      user-hrosten
      user-karim
      user-mkaapu
      user-ktu
      user-bmg
      user-vilvo
      user-vunnyso
    ]);

  # basic auth credentials generated with htpasswd
  sops.secrets.loki_basic_auth.owner = "nginx";

  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "ghaf-log";
    useDHCP = true;
  };

  # sshified user for monitoring server to log in as
  users.users.sshified = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEKd30t0EFmMyULGlecaUX6puIAF4IjynZUo+X9k8h69 monitoring"
    ];
  };

  boot = {
    # use predictable network interface names (eth0)
    kernelParams = ["net.ifnames=0"];
    loader.grub = {
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
  };

  # this server has been reinstalled with 24.05
  system.stateVersion = lib.mkForce "24.05";

  # Grafana
  services.grafana = {
    enable = true;

    settings = {
      server = {
        http_port = 3000;
        http_addr = "127.0.0.1";
        domain = "ghaflogs.vedenemo.dev";
        enforce_domain = true;
      };

      # disable telemetry
      analytics = {
        reporting_enabled = false;
        feedback_links_enabled = false;
      };

      # https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-security-hardening
      security = {
        cookie_secure = true;
        cookie_samesite = "strict";
        login_cookie_name = "__Host-grafana_session";
        strict_transport_security = true;
      };
    };

    provision.datasources.settings.datasources = [
      {
        name = "loki";
        type = "loki";
        isDefault = true;
        url = "http://${config.services.loki.configuration.server.http_listen_address}:${toString config.services.loki.configuration.server.http_listen_port}";
      }
    ];
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "trash@unikie.com";
  };

  services.nginx = {
    virtualHosts = {
      "${config.services.grafana.settings.server.domain}" = {
        enableACME = true;
        forceSSL = true;
        default = true;
        locations."/" = {
          proxyPass = "http://${config.services.grafana.settings.server.http_addr}:${toString config.services.grafana.settings.server.http_port}";
          proxyWebsockets = true;
        };
      };

      "loki.${config.services.grafana.settings.server.domain}" = {
        enableACME = true;
        forceSSL = true;
        basicAuthFile = config.sops.secrets.loki_basic_auth.path;
        locations."/" = {
          proxyPass = "http://${config.services.loki.configuration.server.http_listen_address}:${toString config.services.loki.configuration.server.http_listen_port}";
          proxyWebsockets = true;
        };
      };
    };
  };
}
