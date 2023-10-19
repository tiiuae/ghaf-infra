# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  ...
}: {
  services = {
    nix-serve = {
      enable = true;
      secretKeyFile = config.sops.secrets.cache-sig-key.path;
    };
  };
  networking.firewall.allowedTCPPorts = [5000];
}
