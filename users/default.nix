# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  flake.nixosModules = {
    user-bmg = import ./bmg.nix;
    user-builder = import ./builder.nix;
    user-hrosten = import ./hrosten.nix;
    user-tester = import ./tester.nix;
  };
}
