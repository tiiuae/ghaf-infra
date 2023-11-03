# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  pkgs ?
  # If pkgs is not defined, instanciate nixpkgs from locked commit
  let
    lock = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.nixpkgs.locked;
    nixpkgs = fetchTarball {
      url = "https://github.com/nixos/nixpkgs/archive/${lock.rev}.tar.gz";
      sha256 = lock.narHash;
    };
  in
    import nixpkgs {overlays = [];},
  ...
}:
pkgs.mkShell {
  NIX_CONFIG = "extra-experimental-features = nix-command flakes";
  nativeBuildInputs = with pkgs; [
    git
    nix
    nixos-rebuild
    python3.pkgs.black
    python3.pkgs.colorlog
    python3.pkgs.deploykit
    python3.pkgs.invoke
    python3.pkgs.pycodestyle
    python3.pkgs.pylint
    reuse
    sops
    ssh-to-age
    terraform
  ];
}
