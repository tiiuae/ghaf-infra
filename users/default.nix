# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  flake.nixosModules = {
    user-builder = import ./builder.nix;
    user-hrosten = import ./hrosten.nix;
    user-tester = import ./tester.nix;
    user-jrautiola = import ./jrautiola.nix;
    user-hydra = import ./hydra.nix;
    user-cazfi = import ./cazfi.nix;
    user-mkaapu = import ./mkaapu.nix;
    user-karim = import ./karim.nix;
    user-themisto = import ./themisto.nix;
    user-tervis = import ./tervis.nix;
    user-barna = import ./barna.nix;
    user-mika = import ./mika.nix;
    user-ktu = import ./ktu.nix;
    user-avnik = import ./avnik.nix;
  };
}
