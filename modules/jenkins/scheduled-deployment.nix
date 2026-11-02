# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  options,
  ...
}:
let
  cfg = config.services.ghaf-jenkins;
  # Scheduled deployment drains the controller with a marker that a script in
  # ./casc/scheduled-deployment.yaml reads. The marker is kept in deployment
  # state, survives a baseline reset, and is copied when Jenkins starts.
  drainMarker = "/var/lib/scheduled-deployment/jenkins-drain";
  jenkinsDrainMarker = "${config.services.jenkins.home}/scheduled-deployment-drain";
  jenkinsApi = "${lib.getExe pkgs.curl} -sSf --globoff -H 'X-Forwarded-User: scheduled-deployment' -H 'X-Forwarded-Groups: scheduled-deployment' http://localhost:8081";
  drain = pkgs.writeShellScript "jenkins-drain" ''
    set -euo pipefail
    case $1 in
    start) ${pkgs.coreutils}/bin/touch ${drainMarker} ${jenkinsDrainMarker} ;;
    idle)
      # Every running build, and pipeline step, occupies an executor.
      executors=$(${jenkinsApi}'/computer/api/json?tree=computer[executors[idle],oneOffExecutors[idle]]')
      [[ $executors != *'"idle":false'* ]]
      ;;
    end) ${pkgs.coreutils}/bin/rm -f ${jenkinsDrainMarker} ${drainMarker} ;;
    restore)
      if [[ -e ${drainMarker} ]]; then
        ${pkgs.coreutils}/bin/touch ${jenkinsDrainMarker}
      else
        ${pkgs.coreutils}/bin/rm -f ${jenkinsDrainMarker}
      fi
      ;;
    esac
  '';
in
{
  config = lib.optionalAttrs (options.services ? scheduled-deployment) (
    lib.mkIf (cfg.enable && config.services.scheduled-deployment.enable) {
      services.ghaf-jenkins.auth.groups.scheduled-deployment = [
        "Overall/Read"
        "Job/Read"
      ];
      environment.etc."jenkins/casc/scheduled-deployment.yaml".source = ./casc/scheduled-deployment.yaml;
      systemd.services.jenkins.serviceConfig.ExecStartPre = [ "+${drain} restore" ];
      services.baseline-reset.persistentFiles = [
        "scheduled-deployment/jenkins-drain"
      ];
      services.scheduled-deployment = {
        inherit drain;
        # Jenkins may still be starting. The public URL asks for a login, and
        # the builders that pipelines use trust this controller.
        postDeployChecks = ''
          ${jenkinsApi}/api/json --retry 25 --retry-delay 10 --retry-all-errors -o /dev/null
        ''
        + lib.optionalString cfg.auth.enable ''
          redirect=$(${lib.getExe pkgs.curl} -sS -o /dev/null -w '%{redirect_url}' https://${cfg.auth.domain}/)
          [[ $redirect == https://${cfg.auth.domain}/oauth2/sign_in* ]] || { echo "Unexpected redirect: $redirect"; exit 1; }
        ''
        + lib.concatMapStrings (store: ''
          PATH=${pkgs.openssh}/bin:$PATH nix store info --json --store ${lib.escapeShellArg store} |
            ${lib.getExe pkgs.jq} -e .trusted >/dev/null
        '') (lib.attrValues cfg.remoteStores);
      };
    }
  );
}
