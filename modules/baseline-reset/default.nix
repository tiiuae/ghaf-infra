# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.services.baseline-reset;
  nixDevice = if cfg.nixDevice == null then cfg.rootDevice else cfg.nixDevice;
  state = "/var/lib/baseline-reset";
  bootDevice = toString (config.fileSystems."/boot".device or null);
  mounts = {
    "/" = {
      device = cfg.rootDevice;
      subvolume = "@root";
    };
    "/nix" = {
      device = nixDevice;
      subvolume = "@nix";
    };
    "${state}" = {
      device = cfg.rootDevice;
      subvolume = "@persist";
    };
  };
  command =
    initrd:
    pkgs.writeShellScriptBin "baseline-reset" ''
      export BASELINE_ROOT=${lib.escapeShellArg cfg.rootDevice}
      export BASELINE_NIX=${lib.escapeShellArg nixDevice}
      export BASELINE_BOOT=${lib.escapeShellArg bootDevice}
      export BASELINE_SSH=${if config.services.openssh.enable then "1" else "0"}
      export PATH=${
        if initrd then
          "/bin:/sbin"
        else
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.diffutils
            pkgs.util-linux
            pkgs.btrfs-progs
            config.nix.package
          ]
      }
      exec ${pkgs.bash}/bin/bash ${./baseline-reset.sh} "$@"
    '';
  save = command false;
  early = command true;
  deviceUnits = map (device: "${utils.escapeSystemdPath device}.device") (
    lib.unique [
      cfg.rootDevice
      nixDevice
      bootDevice
    ]
  );
in
{
  options.services.baseline-reset = {
    enable = lib.mkEnableOption "restoring the booted NixOS system on every boot";
    rootDevice = lib.mkOption {
      type = lib.types.str;
      description = "Stable /dev/disk/by-* device containing @root and @persist; provision externally.";
    };
    nixDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Device containing @nix and its baselines, or null to use rootDevice.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (
          path:
          let
            layout = mounts.${path};
            fs = config.fileSystems.${path};
            selectors = lib.filter (option: builtins.match "subvol(id)?=.*" option != null) fs.options;
          in
          fs.device == layout.device
          && fs.fsType == "btrfs"
          && selectors != [ ]
          && lib.all (
            option:
            lib.elem option [
              "subvol=${layout.subvolume}"
              "subvol=/${layout.subvolume}"
            ]
          ) selectors
        ) (builtins.attrNames mounts);
        message = "baseline-reset requires matching devices and @root, @nix, @persist btrfs mounts; align the provisioned disko layout.";
      }
      {
        assertion = lib.all (device: lib.hasPrefix "/dev/disk/by-" device) [
          cfg.rootDevice
          nixDevice
          bootDevice
        ];
        message = "baseline-reset requires stable disk paths for root, Nix and boot.";
      }
      {
        assertion =
          config.boot.loader.systemd-boot.enable
          || (config.boot.loader.grub.enable && !config.boot.loader.grub.efiSupport);
        message = "baseline-reset supports systemd-boot/EFI and GRUB/BIOS.";
      }
      {
        assertion = config.swapDevices == [ ] && config.specialisation == { };
        message = "baseline-reset excludes disk swap and specialisations (zram is allowed).";
      }
      {
        assertion =
          (config.fileSystems."/boot".fsType or "") == "vfat"
          && config.boot.loader.efi.efiSysMountPoint == "/boot";
        message = "baseline-reset requires a separate vfat /boot.";
      }
    ];

    fileSystems = lib.mapAttrs (_: layout: {
      device = lib.mkDefault layout.device;
      fsType = lib.mkDefault "btrfs";
      options = [ "subvol=${layout.subvolume}" ];
      neededForBoot = true;
    }) mounts;

    system.preSwitchChecks.baseline-reset = ''
      exec ${save}/bin/baseline-reset save "$1" "$2"
    '';

    services.openssh.hostKeys = lib.mkIf config.services.openssh.enable (
      lib.mkForce [
        {
          path = "${state}/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ]
    );
    systemd.tmpfiles.rules = [
      "d ${state} 0700 root root -"
      "d ${state}/ssh 0700 root root -"
      # nixos-anywhere only carries /etc/ssh/ssh_host_* into its kexec image.
      "C /etc/ssh/ssh_host_ed25519_key 0600 root root - ${state}/ssh/ssh_host_ed25519_key"
    ];

    boot.initrd.systemd.enable = true;
    boot.initrd.supportedFilesystems = [ "btrfs" ];
    boot.initrd.systemd.storePaths = [
      early
      "${./baseline-reset.sh}"
      pkgs.bash
    ];
    boot.initrd.systemd.extraBin = {
      blkid = "${pkgs.util-linuxMinimal}/bin/blkid";
      findmnt = "${pkgs.util-linuxMinimal}/bin/findmnt";
    };
    boot.initrd.systemd.services.baseline-reset = {
      description = "Restore the booted system baseline before mounting root";
      requiredBy = [ "sysroot.mount" ];
      before = [
        "sysroot.mount"
        "sysroot-nix.mount"
      ];
      after = deviceUnits;
      requires = deviceUnits;
      unitConfig = {
        DefaultDependencies = false;
        OnFailure = "emergency.target";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${early}/bin/baseline-reset initrd";
      };
    };
  };
}
