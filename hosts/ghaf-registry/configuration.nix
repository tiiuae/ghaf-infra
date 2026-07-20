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
    ../registry.nix
    ../hetzner-cloud.nix
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    service-nginx
    team-devenv
  ]);

  sops.defaultSopsFile = ./secrets.yaml;
  system.stateVersion = lib.mkForce "25.11";
  networking.hostName = "ghaf-registry";

  services.zot-registry = {
    clientId = "zot-registry";
    domain = "registry.vedenemo.dev";
    metrics.enable = true;
    storageConfig.storageDriver = {
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
