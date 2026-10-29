# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ self, inputs }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.services.testagent;
  inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) brainstem;

  mkAgent =
    device:
    let
      name = "${cfg.variant}-${device}";
    in
    {
      # bindsTo instead of requires makes the agents stop when the parent service stops
      bindsTo = [ "start-agents.service" ];
      wantedBy = [ "start-agents.service" ];
      after = [ "start-agents.service" ];

      path = [
        inputs.jetpack.legacyPackages.${pkgs.stdenv.hostPlatform.system}.nvidia-jetpack6.board-automation
        brainstem
        inputs.robot-framework.packages.${pkgs.stdenv.hostPlatform.system}.ghaf-robot
        self.packages.${pkgs.stdenv.hostPlatform.system}.policy-checker
        self.packages.${pkgs.stdenv.hostPlatform.system}.verify-signature
      ]
      ++ (with pkgs; [
        curl
        wget
        oras
        jdk
        git
        bashInteractive
        coreutils
        gawk
        util-linux
        nix
        zstd
        jq
        csvkit
        sudo
        openssh
        openssl
        iputils
        netcat
        python3
        usbsdmux
        grafana-loki
      ]);

      serviceConfig = {
        Type = "simple";
        User = "jenkins";
        EnvironmentFile = "-/var/lib/jenkins/jenkins.env";
        WorkingDirectory = "/var/lib/jenkins";
        # The agent reconnects by itself, so that running tests survive a short
        # outage, but exits if that fails for five minutes. Each start fetches
        # the secret again, which changes when the controller is reset.
        Restart = "always";
        RestartSec = 10;
        RestartPreventExitStatus = 6;
        SuccessExitStatus = [ 6 ];
        ExecStart = toString (
          pkgs.writeShellScript "jenkins-connect.sh" # sh
            ''
              if [[ -z "$CONTROLLER" ]]; then
                echo "ERROR: Variable CONTROLLER not configured in /var/lib/jenkins/jenkins.env"
                exit 6
              fi

              mkdir -p "/var/lib/jenkins/agents/${device}"

              # After a reboot or a lost connection, the controller can hold
              # the old connection for minutes, and rejects a new agent
              # process until it is gone. Without the Agent/Disconnect
              # permission, the agent restarts until the controller drops it.
              ssh -i ${config.sops.secrets.ssh_host_ed25519_key.path} ${config.networking.hostName}@''${CONTROLLER#*//} \
                bash -s -- disconnect ${name} <${./drain.sh} || echo "Could not disconnect an earlier connection"

              # connects to controller with ssh and parses the secret from the jnlp file
              JENKINS_SECRET="$(
                ssh -i ${config.sops.secrets.ssh_host_ed25519_key.path} ${config.networking.hostName}@''${CONTROLLER#*//} \
                "curl -f -H 'X-Forwarded-User: ${config.networking.hostName}' -H 'X-Forwarded-Groups: testagents' http://localhost:8081/computer/${name}/jenkins-agent.jnlp | sed 's/.*<application-desc><argument>\([a-z0-9]*\).*/\1\n/'"
              )"
              if [[ -z "$JENKINS_SECRET" ]]; then
                echo "ERROR: Could not fetch the agent secret from $CONTROLLER"
                exit 1
              fi

              # opens a websocket connection to the jenkins controller from this agent
              ${pkgs.jdk}/bin/java \
                -jar agent.jar \
                -url "$CONTROLLER" \
                -name "${name}" \
                -secret "$JENKINS_SECRET" \
                -workDir "/var/lib/jenkins/agents/${device}" \
                -webSocket \
                -noReconnectAfter 5m
            ''
        );
      };
    };
in
{
  options = with lib.types; {
    services.testagent = {
      enable = lib.mkEnableOption "the Ghaf Jenkins test agent";

      # variant such as dbg, dev, prod or release
      # used in the naming of jenkins slaves
      variant = lib.mkOption { type = str; };

      # what hardware devices to create nodes for
      hardware = lib.mkOption { type = listOf str; };

      relayBoard.enable = lib.mkEnableOption "the relay-board exporter";
    };
  };

  config = lib.mkIf cfg.enable {
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
      # map hardware to services
      builtins.listToAttrs (map (hw: lib.nameValuePair "agent-${hw}" (mkAgent hw)) cfg.hardware) // {
        start-agents = {
          # Reconnect after a reboot. Without a controller (never connected, or
          # after `disconnect`) the service and the agents exit with 6.
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          path = [ pkgs.wget ];
          serviceConfig = {
            Type = "oneshot";
            User = "jenkins";
            EnvironmentFile = "-/var/lib/jenkins/jenkins.env";
            WorkingDirectory = "/var/lib/jenkins";
            RemainAfterExit = "yes";
            SuccessExitStatus = [ 6 ];
            ExecStart = toString (
              pkgs.writeShellScript "start-agents.sh" # sh
                ''
                  if [[ -z "$CONTROLLER" ]]; then
                    echo "ERROR: Variable CONTROLLER not configured in /var/lib/jenkins/jenkins.env"
                    exit 6
                  fi

                  echo "Downloading agent.jar from $CONTROLLER"
                  wget "$CONTROLLER/jnlpJars/agent.jar" -O agent.jar
                ''
            );
          };
        };
      };
  };
}
