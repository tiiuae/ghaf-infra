# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Nothing stops new remote builds, so scheduled deployment only waits until
  # no build has run for a minute: no session of the remote build account and
  # no process of a Nix build user.
  drain = pkgs.writeShellApplication {
    name = "builder-drain";
    runtimeInputs = [ pkgs.procps ];
    text = ''
      [[ $1 == idle ]] || exit 0
      for _ in {1..12}; do
        if pgrep -u ${lib.escapeShellArg config.builder.sshUser} >/dev/null || pgrep -G nixbld >/dev/null; then
          exit 1
        fi
        sleep 5
      done
    '';
  };
in
{
  imports = [
    ./tuning.nix
    ./cachix-push.nix
    ../scheduled-deployment
  ];

  options.builder = {
    enable = lib.mkEnableOption "remote Nix builder";
    sshUser = lib.mkOption {
      type = lib.types.str;
      default = "remote-build";
      description = "SSH account used by remote build clients.";
    };
    sshPublicKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH public keys authorized to use the remote build account.";
    };
    sshTrustedCAFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime path to an SSH user CA public-key file to trust, or null to leave CA trust unconfigured.";
    };
    crossCompilation.enable = lib.mkEnableOption "AArch64 emulation and i686 builds";
  };

  config = lib.mkIf config.builder.enable (
    lib.mkMerge [
      {
        users.users.${config.builder.sshUser} = {
          isNormalUser = true;
          openssh.authorizedKeys.keys = config.builder.sshPublicKeys;
        };
        nix.settings.trusted-users = [ config.builder.sshUser ];

        services.scheduled-deployment = {
          drain = lib.getExe drain;
          # Remote build clients log in as the remote build account, which the
          # Nix daemon must trust.
          postDeployChecks = ''
            runuser -u ${lib.escapeShellArg config.builder.sshUser} -- nix store info --store daemon --json | ${lib.getExe pkgs.jq} -e .trusted >/dev/null
          '';
        };

        # Specifies the maximum number of concurrent unauthenticated connections to the SSH daemon.
        # The default of 10 is not enough when multiple clients are building
        # at the same time and can result in dropped connections
        services.openssh.settings.MaxStartups = 100;

        # Increase the maximum number of open files user limit, see ulimit
        security.pam.loginLimits = [
          {
            domain = "*";
            item = "nofile";
            type = "-";
            value = "8192";
          }
        ];
      }
      (lib.mkIf (config.builder.sshTrustedCAFile != null) {
        services.openssh.settings.TrustedUserCAKeys = config.builder.sshTrustedCAFile;
      })
      (lib.mkIf config.builder.crossCompilation.enable {
        boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
        nix.settings.extra-platforms = [ "i686-linux" ];
      })
    ]
  );
}
