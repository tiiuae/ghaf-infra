# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  pkgs,
  inputs,
  lib,
  config,
  ...
}:
let
  # Vendored in, as brainstem isn't suitable for nixpkgs packaging upstream:
  # https://github.com/NixOS/nixpkgs/pull/313643
  brainstem = pkgs.callPackage ../../pkgs/brainstem { };
in
{
  options = {
    # variant such as dev, prod or release
    # used in the naming of jenkins slaves
    services.testagent.variant = lib.mkOption { type = lib.types.str; };
  };

  config = {
    # The Jenkins slave service is very barebones
    # it only installs java and sets up jenkins user
    services.jenkinsSlave.enable = true;

    # Jenkins needs sudo and serial rights to perform the HW tests
    users.users.jenkins.extraGroups = [
      "wheel"
      "dialout"
      "tty"
    ];

    systemd.services =
      let
        mkAgent =
          device:
          let
            name = "${config.services.testagent.variant}-${device}";
          in
          {
            # bindsTo instead of requires makes the agents stop when the parent service stops
            bindsTo = [ "start-agents.service" ];
            wantedBy = [ "start-agents.service" ];
            after = [ "start-agents.service" ];

            path =
              [
                brainstem
                inputs.robot-framework.packages.${pkgs.system}.ghaf-robot
              ]
              ++ (with pkgs; [
                curl
                wget
                jdk
                git
                bashInteractive
                coreutils
                util-linux
                nix
                zstd
                jq
                csvkit
                sudo
                openssh
                iputils
                netcat
                python3
                usbsdmux
                grafana-loki
              ]);

            serviceConfig = {
              Type = "simple";
              User = "jenkins";
              EnvironmentFile = "/var/lib/jenkins/jenkins.env";
              WorkingDirectory = "/var/lib/jenkins";
              Restart = "no";
              SuccessExitStatus = [ 6 ];
              ExecStart = toString (
                pkgs.writeShellScript "jenkins-connect.sh" # sh
                  ''
                    if [[ -z "$CONTROLLER" ]]; then
                      echo "ERROR: Variable CONTROLLER not configured in $(pwd)/jenkins.env"
                      exit 6
                    fi

                    mkdir -p "/var/lib/jenkins/agents/${device}"

                    # connects to controller with ssh and parses the secret from the jnlp file
                    JENKINS_SECRET="$(
                      ssh -i ${config.sops.secrets.ssh_host_ed25519_key.path} ${config.networking.hostName}@''${CONTROLLER#*//} \
                      "curl -H 'X-Forwarded-User: ${config.networking.hostName}' http://localhost:8081/computer/${name}/jenkins-agent.jnlp | sed 's/.*<application-desc><argument>\([a-z0-9]*\).*/\1\n/'"
                    )"

                    # opens a websocket connection to the jenkins controller from this agent
                    ${pkgs.jdk}/bin/java \
                      -jar agent.jar \
                      -url "$CONTROLLER" \
                      -name "${name}" \
                      -secret "$JENKINS_SECRET" \
                      -workDir "/var/lib/jenkins/agents/${device}" \
                      -webSocket
                  ''
              );
            };
          };
      in
      {
        start-agents = {
          path = with pkgs; [ wget ];
          serviceConfig = {
            Type = "oneshot";
            User = "jenkins";
            RemainAfterExit = "yes";
            WorkingDirectory = "/var/lib/jenkins";
            ExecStart = toString (
              pkgs.writeShellScript "start-agents.sh" # sh
                ''
                  if [[ ! -f agent.jar ]]; then
                    echo "Downloading agent.jar"
                    wget -O "$CONTROLLER/jnlpJars/agent.jar"
                  fi
                ''
            );
          };
        };

        # one agent per unique hardware device to act as a lock
        agent-orin-agx = mkAgent "orin-agx";
        agent-orin-nx = mkAgent "orin-nx";
        agent-dell-7330 = mkAgent "dell-7330";
        agent-nuc = mkAgent "nuc";
        agent-lenovo-x1 = mkAgent "lenovo-x1";
      };
  };
}
