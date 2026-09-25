# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  machines,
  self,
  ...
}:
let
  tuning = import ../../lib/nix-tuning.nix { inherit lib; };
  trustedBuilderHost = host: "${host}?trusted=true";

  # Current host sizing: 16 vCPU, 30 GiB RAM, ~337 GiB root disk.
  controllerDisk = tuning.mkDiskThresholds 337;

  # Current release builder sizing:
  # - hetz86-rel-2: 96 vCPU, 251 GiB RAM
  # - hetzarm-rel-1: 16 vCPU, 30 GiB RAM
  x86Builder = tuning.mkBuildLimits {
    cpus = 96;
    ramGiB = 251;
  };
  armBuilder = tuning.mkBuildLimits {
    cpus = 16;
    ramGiB = 30;
  };

  # Keep builder credentials in volatile storage so they do not survive a reset.
  credentialDirectory = "/run/release-builder-credentials";
  x86BuilderSshKey = "${credentialDirectory}/hetz86-rel-2-builder";
  armBuilderSshKey = "${credentialDirectory}/hetzarm-rel-1-builder";
in
{
  imports = [
    ./disk-config.nix
    ../common.nix
    ../cloud.nix
    ../signing.nix
    self.nixosModules.baseline-reset
  ];

  system.stateVersion = "26.11";
  networking.hostName = "hetzci-release";
  nix.caches = [
    "nixos-org"
    "ghaf-release"
  ];

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      ssh_private_key.owner = "root";
      cachix-auth-token.owner = "jenkins";
      jenkins_archive_access_key.owner = "jenkins";
      jenkins_archive_secret_key.owner = "jenkins";
      oauth2_proxy_client_secret.owner = "oauth2-proxy";
      oauth2_proxy_cookie_secret.owner = "oauth2-proxy";
      oci_registry_password.owner = "jenkins";
    };
  };

  services.ghaf-jenkins = {
    envType = "release";
    url = "https://ci-release.vedenemo.dev";
    auth = {
      enable = true;
      clientID = "hetzci-release";
      clientSecretFile = config.sops.secrets.oauth2_proxy_client_secret.path;
      cookieSecretFile = config.sops.secrets.oauth2_proxy_cookie_secret.path;
      domain = "ci-release.vedenemo.dev";
    };
    integrations.cachix = {
      enable = true;
      tokenFile = config.sops.secrets.cachix-auth-token.path;
    };
    archive = {
      enable = true;
      s3Credentials = {
        accessKeyFile = config.sops.secrets.jenkins_archive_access_key.path;
        secretKeyFile = config.sops.secrets.jenkins_archive_secret_key.path;
      };
    };
    registry.passwordFile = config.sops.secrets.oci_registry_password.path;
    nodes.testagentHosts = [ "release" ];
    pipelines = [
      "ghaf-hw-test"
      "ghaf-release-candidate"
      "ghaf-release-publish"
    ];
  };

  hetzci.signing.proxy.enable = true;

  services.baseline-reset = {
    enable = true;
    rootDevice = "/dev/disk/by-partlabel/disk-os-root";
  };

  # Configure /var/lib/caddy in /etc/fstab for persistent caddy state.
  fileSystems."/var/lib/caddy" = {
    device = "/dev/disk/by-id/scsi-0HC_Volume_103219547";
    fsType = "ext4";
    options = [
      "x-systemd.makefs"
      "x-systemd.growfs"
    ];
  };

  nix.settings.max-jobs = lib.mkForce 0;
  nix.settings.min-free = lib.mkOverride 60 controllerDisk.minFreeBytes;
  nix.settings.max-free = lib.mkOverride 60 controllerDisk.maxFreeBytes;

  # install-release creates the generated keys here after every controller reset.
  systemd.tmpfiles.rules = [
    "d ${credentialDirectory} 0750 root jenkins -"
  ];
  # Keep Jenkins stopped after boot until install-release has validated the new
  # builder credentials, then starts it explicitly.
  systemd.services.jenkins.wantedBy = lib.mkForce [ ];

  # Configure (release) remote builders
  nix = {
    distributedBuilds = true;
    buildMachines =
      let
        commonOptions = {
          protocol = "ssh-ng";
          supportedFeatures = [
            "kvm"
            "nixos-test"
            "benchmark"
            "big-parallel"
          ];
        };
      in
      [
        (
          commonOptions
          // {
            hostName = trustedBuilderHost "hetz86-rel-2";
            system = "x86_64-linux";
            maxJobs = x86Builder.maxJobs;
            speedFactor = 12;
            sshUser = "hetz86-rel-2-builder";
            sshKey = x86BuilderSshKey;
          }
        )
        (
          commonOptions
          // {
            hostName = trustedBuilderHost "hetzarm-rel-1";
            system = "aarch64-linux";
            maxJobs = armBuilder.maxJobs;
            speedFactor = 2;
            sshUser = "hetzarm-rel-1-builder";
            sshKey = armBuilderSshKey;
          }
        )
      ];
  };

  programs.ssh = {
    # Known builder host public keys, these go to /root/.ssh/known_hosts
    knownHosts = {
      "hetz86-rel-2".publicKey = machines.hetz86-rel-2.publicKey;
      "${machines.hetz86-rel-2.ip}".publicKey = machines.hetz86-rel-2.publicKey;
      "hetzarm-rel-1".publicKey = machines.hetzarm-rel-1.publicKey;
      "${machines.hetzarm-rel-1.ip}".publicKey = machines.hetzarm-rel-1.publicKey;
    };

    # Custom options to /etc/ssh/ssh_config
    extraConfig = lib.mkAfter ''
      Host hetz86-rel-2
      Hostname ${machines.hetz86-rel-2.ip}
      Host hetzarm-rel-1
      Hostname ${machines.hetzarm-rel-1.ip}
    '';
  };
}
