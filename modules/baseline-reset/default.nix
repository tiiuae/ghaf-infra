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
  lower = "/.baseline-reset/lower";
  writableNix = "/.baseline-reset/nix-writable";
  rootMapper = "/dev/mapper/baseline-root";
  nixMapper = "/dev/mapper/baseline-nix";
  bootDevice = toString (config.fileSystems."/boot".device or null);
  validSubvolume =
    fs: device: subvolume:
    let
      selectors = lib.filter (option: builtins.match "subvol(id)?=.*" option != null) fs.options;
    in
    fs.device == device
    && fs.fsType == "btrfs"
    && selectors != [ ]
    && lib.all (
      option:
      lib.elem option [
        "subvol=${subvolume}"
        "subvol=/${subvolume}"
      ]
    ) selectors;
  command =
    initrd:
    pkgs.writeShellScriptBin "baseline-reset" ''
      export BASELINE_ROOT=${lib.escapeShellArg cfg.rootDevice}
      export BASELINE_NIX=${lib.escapeShellArg nixDevice}
      export BASELINE_BOOT=${lib.escapeShellArg bootDevice}
      export BASELINE_ROOT_WRITABLE_PARTUUID=${lib.escapeShellArg cfg.rootWritablePartUUID}
      export BASELINE_NIX_WRITABLE_PARTUUID=${
        lib.escapeShellArg (if cfg.nixWritablePartUUID == null then "" else cfg.nixWritablePartUUID)
      }
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
            pkgs.cryptsetup
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
      description = "Stable device containing @persist and, without nixDevice, the Nix baselines.";
    };
    nixDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Persistent device containing Nix baselines and @lower, or null to use rootDevice.";
    };
    rootWritablePartUUID = lib.mkOption {
      type = lib.types.str;
      description = "Fixed GPT PARTUUID of the per-boot writable root partition.";
    };
    nixWritablePartUUID = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Fixed GPT PARTUUID of a separate per-boot writable Nix partition.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          validSubvolume config.fileSystems.${lower} nixDevice "@lower"
          && lib.elem "ro" config.fileSystems.${lower}.options
          && validSubvolume config.fileSystems.${state} cfg.rootDevice "@persist";
        message = "baseline-reset requires matching @persist and read-only @lower btrfs mounts.";
      }
      {
        assertion =
          config.fileSystems."/".device == rootMapper
          && config.fileSystems."/".fsType == "btrfs"
          && config.fileSystems."/nix".overlay.lowerdir == [ lower ]
          && config.fileSystems."/nix".overlay.upperdir == "${writableNix}/upper"
          && config.fileSystems."/nix".overlay.workdir == "${writableNix}/work";
        message = "baseline-reset requires an encrypted btrfs root and the configured /nix overlay.";
      }
      {
        assertion =
          (cfg.nixDevice == null) == (cfg.nixWritablePartUUID == null)
          && (
            cfg.nixWritablePartUUID == null
            || (
              config.fileSystems.${writableNix}.device == nixMapper
              && config.fileSystems.${writableNix}.fsType == "btrfs"
            )
          );
        message = "baseline-reset requires a separate encrypted Nix mount exactly when nixDevice is set.";
      }
      {
        assertion =
          builtins.match "[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}" cfg.rootWritablePartUUID != null
          && (
            cfg.nixWritablePartUUID == null
            || (
              builtins.match "[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}" cfg.nixWritablePartUUID != null
              && cfg.rootWritablePartUUID != cfg.nixWritablePartUUID
            )
          );
        message = "baseline-reset requires distinct lowercase GPT PARTUUIDs for writable partitions.";
      }
      {
        assertion = lib.all (device: lib.hasPrefix "/dev/disk/by-" device) [
          cfg.rootDevice
          nixDevice
          bootDevice
        ];
        message = "baseline-reset requires stable paths for persistent root, Nix and boot devices.";
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

    fileSystems = {
      "${lower}" = {
        device = lib.mkDefault nixDevice;
        fsType = lib.mkDefault "btrfs";
        options = lib.mkDefault [
          "subvol=@lower"
          "ro"
        ];
        neededForBoot = true;
      };
      "${state}" = {
        device = lib.mkDefault cfg.rootDevice;
        fsType = lib.mkDefault "btrfs";
        options = lib.mkDefault [ "subvol=@persist" ];
        neededForBoot = true;
      };
      "/" = {
        device = lib.mkDefault rootMapper;
        fsType = lib.mkDefault "btrfs";
        neededForBoot = true;
      };
      "/nix" = {
        overlay = {
          lowerdir = [ lower ];
          upperdir = "${writableNix}/upper";
          workdir = "${writableNix}/work";
        };
        neededForBoot = true;
      };
    }
    // lib.optionalAttrs (cfg.nixWritablePartUUID != null) {
      "${writableNix}" = {
        device = lib.mkDefault nixMapper;
        fsType = lib.mkDefault "btrfs";
        neededForBoot = true;
      };
    };

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
    boot.initrd.availableKernelModules = [
      "dm-crypt"
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
      "aes_ti"
      "aesni_intel"
      "cbc"
      "xts"
    ];
    boot.initrd.supportedFilesystems = [ "btrfs" ];
    boot.initrd.systemd.storePaths = [
      early
      "${./baseline-reset.sh}"
      pkgs.bash
    ];
    boot.initrd.systemd.extraBin = {
      blkid = "${pkgs.util-linuxMinimal}/bin/blkid";
      findmnt = "${pkgs.util-linuxMinimal}/bin/findmnt";
      cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
    };
    boot.initrd.systemd.services.baseline-reset = {
      description = "Restore the booted system baseline before mounting root";
      requiredBy = [ "sysroot.mount" ];
      before = [
        "sysroot.mount"
        "sysroot-nix.mount"
        "${utils.escapeSystemdPath "/sysroot${lower}"}.mount"
      ]
      ++ lib.optional (
        cfg.nixWritablePartUUID != null
      ) "${utils.escapeSystemdPath "/sysroot${writableNix}"}.mount";
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
