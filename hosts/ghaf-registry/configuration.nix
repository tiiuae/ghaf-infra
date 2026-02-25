# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  self,
  lib,
  inputs,
  ...
}:
let
  inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) zot;
  zotDataDir = "/var/lib/zot";
  zotConfig = {
    storage = {
      rootDirectory = zotDataDir;
      gc = true;
      gcDelay = "1h";
    };

    http = {
      address = "127.0.0.1";
      port = "5000";
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
    ../hetzner-cloud.nix
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    service-nginx
    team-devenv
  ]);

  sops.defaultSopsFile = ./secrets.yaml;
  system.stateVersion = lib.mkForce "25.11";
  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "ghaf-registry";

  services.nginx.virtualHosts."registry.vedenemo.dev" = {
    enableACME = true;
    forceSSL = true;
    default = true;

    # OCI registry API: allow anonymous pulls, require auth for pushes
    # locations."/v2/" = {
    #   proxyPass = "http://127.0.0.1:${zotConfig.http.port}";
    #       # };
    locations."/" = {
      proxyPass = "http://127.0.0.1:${zotConfig.http.port}";
      extraConfig = ''
        client_max_body_size 0;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };

  environment.systemPackages = [
  ];

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
      WorkingDirectory = zotDataDir;
      ReadWritePaths = [ zotDataDir ];
    };
  };
}
