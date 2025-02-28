# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  flake.nixosModules = {
    user-hrosten = import ./hrosten.nix;
    user-jrautiola = import ./jrautiola.nix;
    user-cazfi = import ./cazfi.nix;
    user-ktu = import ./ktu.nix;
    user-avnik = import ./avnik.nix;
    user-flokli = import ./flokli.nix;
    user-vjuntunen = import ./vjuntunen.nix;
    user-mariia = import ./mariia.nix;
    user-leivos = import ./leivos.nix;
    user-vunnyso = import ./vunnyso.nix;
    user-bmg = import ./bmg.nix;
    user-fayad = import ./fayad.nix;
    user-github = import ./github.nix;
    user-remote-build = import ./remote-build.nix;
    user-alextserepov = import ./alextserepov.nix;
  };
}
