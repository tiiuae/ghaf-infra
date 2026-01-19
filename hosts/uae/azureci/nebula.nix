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
    self.nixosModules.service-nebula
  ];

  sops = {
    secrets = lib.mkMerge [
      (lib.mkIf config.nebula.enable {
        nebula-cert.owner = config.nebula.user;
        nebula-key.owner = config.nebula.user;
      })
    ];
  };

  nebula = {
    enable = lib.mkDefault true;
    cert = config.sops.secrets.nebula-cert.path;
    key = config.sops.secrets.nebula-key.path;
  };
}
