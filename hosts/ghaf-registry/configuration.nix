# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  inputs,
  ...
}:
{
  imports = [
    ./disk-config.nix
    self.nixosModules.hetzner-cloud
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    zot-registry
    openssh
    team-devenv
  ]);

  sops.defaultSopsFile = ./secrets.yaml;
  system.stateVersion = lib.mkForce "25.11";
  networking.hostName = "ghaf-registry";

  services.zot-registry = {
    clientId = "zot-registry";
    domain = "registry.vedenemo.dev";
    metrics.enable = true;
    extraConfig.storage.storageDriver = {
      name = "s3";
      bucket = "oci-artifacts";
      region = "hel1";
      forcepathstyle = true;
      regionendpoint = "https://hel1.your-objectstorage.com";
      chunksize = toString (32 * 1024 * 1024);
    };
  };

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };
}
