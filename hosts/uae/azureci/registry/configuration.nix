# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  inputs,
  modulesPath,
  lib,
  config,
  ...
}:
let
  inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) zot;

  zotDataDir = "/var/lib/zot";
  zotPort = 5000;

  zotConfig = {
    storage = {
      # Use local filesystem storage until aws s3 me-central-1 outage is resolved
      rootDirectory = zotDataDir;

      # Use AWS s3 storage as backend
      #storageDriver = {
      #  name = "s3";
      #  bucket = "ghaf-infra-artifacts";
      #  region = "me-central-1";
      #  forcepathstyle = true;
      #  secure = true;
      #  chunksize = toString (32 * 1024 * 1024);
      #};

      dedupe = false;
      gc = true;
      gcInterval = "1h";
      retention = {
        delay = "24h";
        policies = [
          {
            repositories = [ "ghaf/**" ];
            deleteReferrers = true;
            deleteUntagged = true;
            keepTags = [
              {
                patterns = [ "release-.*" ];
                # Keep at least three builds in each repository
                mostRecentlyPushedCount = 3;
                # Keep everything for at least a week
                pushedWithin = "168h";
              }
              {
                patterns = [ "prod-.*" ];
                mostRecentlyPushedCount = 3;
                pushedWithin = "168h";
              }
              {
                patterns = [ "dev-.*" ];
                mostRecentlyPushedCount = 3;
                pushedWithin = "168h";
              }
              {
                patterns = [
                  "vm-.*"
                  "dbg-.*"
                ];
                pushedWithin = "24h";
              }
            ];
          }
        ];
      };
    };

    http = {
      address = "127.0.0.1";
      port = zotPort;
      externalUrl = "https://registry.uaenorth.cloudapp.azure.com";

      auth = {
        htpasswd.path = config.sops.secrets.zot-htpasswd.path;

        openid.providers.oidc = {
          name = "Vedenemo Auth";
          issuer = "https://auth.vedenemo.dev";
          credentialsFile = config.sops.templates."zot-oidc-credentials.json".path;
          keypath = "";
          scopes = [
            "openid"
            "profile"
            "email"
            "groups"
          ];
        };
      };

      accessControl = {
        repositories = {
          "ghaf/**" = {
            policies = [
              {
                users = [ "jenkins" ];
                actions = [
                  "read"
                  "create"
                  "update"
                  "delete"
                ];
              }
            ];
            defaultPolicy = [ "read" ];
            anonymousPolicy = [ "read" ];
          };
          "**" = {
            defaultPolicy = [ "read" ];
            anonymousPolicy = [ "read" ];
          };
        };
      };
    };
    log = {
      level = "info";
    };
    extensions = {
      ui.enable = true;
      search.enable = true;
      metrics.enable = true;
    };
  };
  zotConfigFile = pkgs.writeText "zot_config.json" (builtins.toJSON zotConfig);
in
{
  imports = [
    ./disk-config.nix
    ../../azureci/azure-common.nix
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    service-nginx
    team-devenv
  ]);

  sops.defaultSopsFile = ./secrets.yaml;

  # this server has been initialized with 25.11 with nixos-anywhere
  system.stateVersion = lib.mkForce "25.11";

  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "uae-azureci-registry";
  };

  sops = {
    secrets = {
      auth-client-secret.owner = "zot";
      zot-s3-credentials.owner = "zot";
      zot-htpasswd.owner = "zot";
    };
    templates."zot-oidc-credentials.json" = {
      owner = "zot";
      content = builtins.toJSON {
        clientid = "uae-zot-registry";
        clientsecret = config.sops.placeholder.auth-client-secret;
      };
    };
  };

  services.nginx.virtualHosts."registry.uaenorth.cloudapp.azure.com" = {
    enableACME = true;
    forceSSL = true;
    default = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString zotPort}";
      # nginx buffering causes pulls to fail occasionally when using s3 backend
      extraConfig = ''
        client_max_body_size 0;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_max_temp_file_size 0;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        client_body_timeout 3600s;
      '';
    };
  };

  users.groups.zot = { };
  users.users.zot = {
    isSystemUser = true;
    group = "zot";
    home = zotDataDir;
    createHome = true;
  };

  systemd.tmpfiles.rules = [
    "d ${zotDataDir} 0750 zot zot - -"
  ];

  systemd.services.zot = {
    description = "zot OCI registry";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      User = "zot";
      Group = "zot";

      ExecStart = "${zot}/bin/zot serve ${zotConfigFile}";
      Restart = "always";
      RestartSec = "5s";

      UMask = "0027";
      EnvironmentFile = config.sops.secrets.zot-s3-credentials.path;
      WorkingDirectory = zotDataDir;
      ReadWritePaths = [ zotDataDir ];
    };
  };

  boot = {
    # use predictable network interface names (eth0)
    kernelParams = [ "net.ifnames=0" ];
    loader.grub = {
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
  };

  environment.systemPackages = with pkgs; [
    screen
    tmux
    cryptsetup
    sg3_utils
    dnsutils
    inetutils
    pciutils
    dmidecode
    jq
  ];
}
