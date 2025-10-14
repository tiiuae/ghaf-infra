# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # list of systems to emulate using binfmt
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # extra nix build platforms to enable
  nix.settings.extra-platforms = [ "i686-linux" ];
}
