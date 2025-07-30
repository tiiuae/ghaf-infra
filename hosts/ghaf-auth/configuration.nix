# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  modulesPath,
  lib,
  config,
  ...
}:
let
  domain = "auth.vedenemo.dev";
in
{
  imports =
    [
      ./disk-config.nix
      (modulesPath + "/profiles/qemu-guest.nix")
      inputs.sops-nix.nixosModules.sops
      inputs.disko.nixosModules.disko
    ]
    ++ (with self.nixosModules; [
      common
      service-monitoring
      service-openssh
      service-nginx
      team-devenv
    ]);

  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets = {
    dex_env.owner = "dex";
    vedenemo_loki_password.owner = "promtail";
  };

  # this server has been installed with 24.1
  system.stateVersion = lib.mkForce "24.11";

  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "ghaf-auth";
    useDHCP = true;
  };

  boot = {
    # use predictable network interface names (eth0)
    kernelParams = [ "net.ifnames=0" ];
    loader.grub = {
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
  };

  services.monitoring = {
    metrics = {
      enable = true;
      ssh = true;
    };
    logs = {
      enable = true;
      lokiAddress = "https://monitoring.vedenemo.dev";
      auth.password_file = config.sops.secrets.vedenemo_loki_password.path;
    };
  };

  services.dex = {
    enable = true;

    environmentFile = config.sops.secrets.dex_env.path;

    settings = {
      issuer = "https://${domain}";
      enablePasswordDB = false;

      storage = {
        type = "sqlite3";
        config.file = "/var/lib/dex/dex.db";
      };

      web = {
        http = "127.0.0.1:5556";
      };

      oauth2 = {
        skipApprovalScreen = true;
        alwaysShowLoginScreen = false;
      };

      connectors = [
        {
          type = "github";
          id = "github";
          name = "GitHub";
          config = {
            useLoginAsID = true;
            clientID = "$GITHUB_CLIENT_ID";
            clientSecret = "$GITHUB_CLIENT_SECRET";
            redirectURI = "https://${domain}/callback";
            orgs = [
              { name = "tiiuae"; }
            ];
            teamNameField = "slug";
          };
        }
      ];

      staticClients = [
        {
          id = "ghaf-jenkins-controller-uaenorth";
          name = "Ghaf Jenkins controller (uaenorth)";
          redirectURIs =
            map (env: "https://ghaf-jenkins-controller-${env}.uaenorth.cloudapp.azure.com/oauth2/callback")
              [
                "dev"
                "prod"
                "release"
              ];
          secretEnv = "JENKINS_CONTROLLER_AUTH_SECRET";
        }
        {
          id = "ghaf-jenkins-controller-northeurope";
          name = "Ghaf Jenkins controller (northeurope)";
          redirectURIs =
            map (env: "https://ghaf-jenkins-controller-${env}.northeurope.cloudapp.azure.com/oauth2/callback")
              [
                "release"
                "alextserepov"
                "cazfi"
                "flokli"
                "henri"
                "jrautiola"
                "kaitusa"
                "vjuntunen"
                "fayad"
              ];
          secretEnv = "JENKINS_CONTROLLER_AUTH_SECRET";
        }
        {
          id = "hetzci-prod";
          name = "ci-prod.vedenemo.dev";
          redirectURIs = [ "https://ci-prod.vedenemo.dev/oauth2/callback" ];
          secretEnv = "JENKINS_CONTROLLER_AUTH_SECRET";
        }
        {
          id = "hetzci-dev";
          name = "ci-dev.vedenemo.dev";
          redirectURIs = [ "https://ci-dev.vedenemo.dev/oauth2/callback" ];
          secretEnv = "JENKINS_CONTROLLER_AUTH_SECRET";
        }
      ];
    };
  };

  systemd.services.dex.serviceConfig = {
    StateDirectory = "dex";
    User = "dex";
    Group = "dex";
  };

  users.users.dex = {
    isSystemUser = true;
    group = "dex";
  };

  users.groups.dex = { };

  services.nginx = {
    virtualHosts = {
      "auth.vedenemo.dev" = {
        enableACME = true;
        forceSSL = true;
        default = true;
        locations."/" = {
          proxyPass = "http://${config.services.dex.settings.web.http}";
        };
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "trash@unikie.com";
  };
}
