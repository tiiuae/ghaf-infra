# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  ...
}:
{
  imports =
    [
      ../ficolo.nix
      ../cross-compilation.nix
      ../builders-common.nix
    ]
    ++ (with self.nixosModules; [
      user-github
      user-remote-build
    ]);

  # build2 specific configuration

  networking.hostName = "build2";

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };
}
