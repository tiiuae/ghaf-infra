# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  self,
  ...
}:
{
  imports = [
    self.nixosModules.nebula
  ];

  nebula.enable = lib.mkDefault true;
}
