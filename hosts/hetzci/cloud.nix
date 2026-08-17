# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  self,
  ...
}:
{
  imports = [
    self.nixosModules.nebula
    self.nixosModules.hetzner-cloud
  ];

  sops.secrets = lib.mkIf config.services.monitoring.logs.enable {
    loki_password.owner = "alloy";
  };

  services.monitoring = {
    metrics.enable = lib.mkDefault true;
    logs.enable = lib.mkDefault true;
  };

  nebula.enable = lib.mkDefault true;
}
