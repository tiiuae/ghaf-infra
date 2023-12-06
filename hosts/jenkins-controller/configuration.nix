# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  modulesPath,
  ...
}: {
  imports = ["${modulesPath}/virtualisation/azure-config.nix"];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # enable cloud-init, so instance metadata is set accordingly and we can use
  # cloud-config for ssh key management.
  services.cloud-init.enable = true;

  system.stateVersion = "23.05";
}
