# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-FileCopyrightText: 2020-2023 Eelco Dolstra and the flake-compat contributors
# SPDX-License-Identifier: MIT
# This file originates from:
# https://github.com/nix-community/flake-compat
# This file provides backward compatibility to nix < 2.4 clients
{
  system ? builtins.currentSystem,
}:
let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);

  inherit (lock.nodes.flake-compat.locked)
    owner
    repo
    rev
    narHash
    ;

  flake-compat = fetchTarball {
    url = "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz";
    sha256 = narHash;
  };

  flake = import flake-compat {
    inherit system;
    src = ./.;
  };
in
flake.defaultNix
