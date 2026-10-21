# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.scheduled-deployment;
  runner = pkgs.writeShellApplication {
    name = "scheduled-deployment-runner";
    runtimeInputs = with pkgs; [
      coreutils
      gitMinimal
      gnugrep
      gnused
      util-linux
      config.nix.package
      config.systemd.package
    ];
    text = ''
      export DEPLOY_REPOSITORY=${lib.escapeShellArg cfg.repository}
      export DEPLOY_HOST=${lib.escapeShellArg config.networking.hostName}
    ''
    + builtins.readFile ./scheduled-deployment.sh;
  };
  command = pkgs.writeShellApplication {
    name = "scheduled-deployment";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      state=/var/lib/scheduled-deployment
      case "''${1-}" in
      hold)
        shift
        [[ $# -gt 0 ]] || { echo 'A hold reason is required' >&2; exit 1; }
        echo "''${SUDO_USER:-$(id -un)} $(date --utc --iso-8601=seconds): $*" >"$state/hold"
        # A run checks the hold under this lock before activation, so a run
        # that has not reached activation stops there. Wait for one that has.
        flock "$state/activation.lock" true
        ;;
      release) rm -f "$state/hold" ;;
      *) echo 'Usage: scheduled-deployment hold <reason> | release' >&2; exit 1 ;;
      esac
    '';
  };
  checks = pkgs.writeShellScript "scheduled-deployment-checks" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ config.systemd.package ]}:$PATH
    systemctl is-active --quiet sshd.service
    ${lib.concatMapStringsSep "\n" (
      name: "systemctl is-active --quiet ${lib.escapeShellArg "nebula@${name}.service"}"
    ) (lib.attrNames (lib.filterAttrs (_: network: network.enable) config.services.nebula.networks))}
    ${cfg.postDeployChecks}
  '';
in
{
  options.services.scheduled-deployment = {
    enable = lib.mkEnableOption "weekly self-deployment from main";
    window = lib.mkOption {
      type = lib.types.str;
      default = "Tue *-*-* 05..08:00,30:00 UTC";
      description = "systemd OnCalendar window; a deployed or up-to-date run suppresses runs for 24 hours.";
    };
    postDeployChecks = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Shell checks run as root after activation; a nonzero exit fails deployment.";
    };
    repository = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/tiiuae/ghaf-infra";
      description = "Public Git repository with the main branch (no credentials).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(config.services.baseline-reset.enable or false);
        message = "scheduled-deployment does not support baseline-reset hosts.";
      }
    ];
    environment.systemPackages = [ command ];
    # Read checks from the activated system, including after a reboot.
    environment.etc."scheduled-deployment/checks".source = checks;
    systemd.tmpfiles.rules = [
      "d /var/lib/scheduled-deployment 0700 root root -"
      "d /run/ghaf-deployment-metrics 0755 root root -"
    ];
    systemd.services.scheduled-deployment = {
      description = "Deploy this host from a pinned main commit";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      # Switching must not stop the process performing activation or rollback.
      restartIfChanged = false;
      stopIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe runner} run";
        TimeoutStartSec = "infinity";
      };
    };
    systemd.timers.scheduled-deployment = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = cfg.window;
    };
    systemd.services.scheduled-deployment-verify = {
      description = "Verify a pending deployment and restore its metrics after boot";
      after = [ "multi-user.target" ];
      restartIfChanged = false;
      stopIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe runner} verify";
        TimeoutStartSec = "infinity";
      };
    };
    systemd.timers.scheduled-deployment-verify = {
      wantedBy = [ "timers.target" ];
      # Allow boot services to settle before checking for failed units.
      timerConfig.OnBootSec = "2min";
    };
  };
}
