# SPDX-FileCopyrightText: 2003-2024 Eelco Dolstra and the Nixpkgs/NixOS contributors
# SPDX-License-Identifier: MIT
{
  stdenv,
  lib,
  buildGoModule,
  buildPackages,
  fetchFromGitHub,
  installShellFiles,
  makeWrapper,
  ...
}:
# Introduce a vendored-in expression of a (more recent version of) rclone,
# including the patch for socket activation sent upstream at
# https://github.com/rclone/rclone/pull/7801.
#
# The patch doesn't apply cleanly on 1.64.2 (what our nixpkgs points to),
# and would result in a change of vendorHash (only in this old version).
#
# Overriding vendorHash using overrideAttrs is broken, due to
# https://github.com/NixOS/nixpkgs/issues/86349.
#
# Just vendor in a (simplified) expression. Can be replaced with just the patch
# once nixpkgs moves to 23.05.
buildGoModule rec {
  pname = "rclone";
  version = "1.66.0";

  src = fetchFromGitHub {
    owner = "rclone";
    repo = "rclone";
    rev = "v${version}";
    hash = "sha256-75RnAROICtRUDn95gSCNO0F6wes4CkJteNfUN38GQIY=";
  };

  patches = [
    # https://github.com/rclone/rclone/pull/7801
    ./http-socket-activation.patch
  ];

  vendorHash = "sha256-zGBwgIuabLDqWbutvPHDbPRo5Dd9kNfmgToZXy7KVgI=";

  subPackages = ["."];

  outputs = ["out" "man"];

  nativeBuildInputs = [installShellFiles makeWrapper];

  ldflags = ["-s" "-w" "-X github.com/rclone/rclone/fs.Version=${version}"];

  postInstall = let
    rcloneBin =
      if stdenv.buildPlatform.canExecute stdenv.hostPlatform
      then "$out"
      else lib.getBin buildPackages.rclone;
  in ''
    installManPage rclone.1
    for shell in bash zsh fish; do
      ${rcloneBin}/bin/rclone genautocomplete $shell rclone.$shell
      installShellCompletion rclone.$shell
    done

    # filesystem helpers
    ln -s $out/bin/rclone $out/bin/rclonefs
    ln -s $out/bin/rclone $out/bin/mount.rclone
  '';
}
