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
    self.nixosModules.nebula
  ];

  sops.secrets = lib.mkIf config.services.monitoring.logs.enable {
    loki_password.owner = "alloy";
  };

  services.monitoring = {
    metrics.enable = lib.mkDefault true;
    logs = {
      enable = lib.mkDefault true;
      lokiAddress = lib.mkDefault defaultLoki;
      auth.password_file = config.sops.secrets.loki_password.path;
    };
  };

  nebula.enable = lib.mkDefault true;
}
