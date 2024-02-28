# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  inputs,
  pkgs,
  ...
}: {
  services = {
    nix-serve = {
      enable = true;
      package = inputs.nix-serve-ng.packages.${pkgs.system}.default;
      secretKeyFile = config.sops.secrets.cache-sig-key.path;
    };
  };
  networking.firewall.allowedTCPPorts = [5000];
}
