# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  flake.nixosModules = {
    service-nginx = ./nginx;
    service-monitoring = ./monitoring;
    service-openssh = ./openssh;
    service-nebula = ./nebula;
  };
}
