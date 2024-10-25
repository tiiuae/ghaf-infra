# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ self, ... }:
{
  imports =
    [
      ../ficolo.nix
      ../cross-compilation.nix
      ../builders-common.nix
    ]
    ++ (with self.nixosModules; [
      user-themisto
    ]);

  # build4 specific configuration

  networking.hostName = "build4";

}
