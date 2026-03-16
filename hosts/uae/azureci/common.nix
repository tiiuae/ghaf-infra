# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  self,
  machines,
  ...
}:
let
  defaultLoki = "http://${machines.ghaf-monitoring.nebula_ip}:3100";
in
{
  imports = [
    self.nixosModules.service-nebula
    self.nixosModules.service-monitoring
  ];

  services.monitoring.logs.lokiAddress = lib.mkDefault defaultLoki;

  sops = {
    secrets = lib.mkMerge [
      (lib.mkIf config.services.monitoring.logs.enable {
        loki_password.owner = "alloy";
      })
      (lib.mkIf config.nebula.enable {
        nebula-cert.owner = config.nebula.user;
        nebula-key.owner = config.nebula.user;
      })
    ];
  };

  services.monitoring = {
    metrics.enable = lib.mkDefault true;
    logs.enable = lib.mkDefault true;
  };

  nebula = {
    enable = lib.mkDefault true;
    cert = config.sops.secrets.nebula-cert.path;
    key = config.sops.secrets.nebula-key.path;
  };
}
