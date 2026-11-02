# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ self, inputs }:
{
  pkgs,
  lib,
  config,
  options,
  ...
}:
let
  cfg = config.services.testagent;
  agentPackages = [
    inputs.robot-framework.packages.${pkgs.stdenv.hostPlatform.system}.ghaf-robot
    self.packages.${pkgs.stdenv.hostPlatform.system}.policy-checker
    self.packages.${pkgs.stdenv.hostPlatform.system}.verify-signature
  ]
  ++
    lib.optional cfg.tooling.jetson.enable
      inputs.jetpack.legacyPackages.${pkgs.stdenv.hostPlatform.system}.nvidia-jetpack6.board-automation
  ++
    lib.optional cfg.tooling.brainstem.enable
      self.packages.${pkgs.stdenv.hostPlatform.system}.brainstem
  ++ lib.optional cfg.tooling.usbSdmux.enable pkgs.usbsdmux
  ++
    lib.optional cfg.tooling.relayboard
      inputs.robot-framework.packages.${pkgs.stdenv.hostPlatform.system}.KMTronic
  ++ cfg.extraPackages;
  mkAgent =
    device:
    let
      name = "${cfg.nodeNamePrefix}-${device}";
    in
    {
      # bindsTo instead of requires makes the agents stop when the parent service stops
      bindsTo = [ "start-agents.service" ];
      wantedBy = [ "start-agents.service" ];
      after = [ "start-agents.service" ];

      path =
        agentPackages
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
          grafana-loki
        ]);

      serviceConfig = {
        Type = "simple";
        User = "jenkins";
        BindReadOnlyPaths = lib.mapAttrsToList (name: file: "${file}:/run/secrets/${name}") (
          lib.filterAttrs (name: file: file != "/run/secrets/${name}") cfg.testCredentialFiles
        );
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
              ssh -i ${lib.escapeShellArg cfg.controllerSshKeyFile} ${config.networking.hostName}@''${CONTROLLER#*//} \
                bash -s -- disconnect ${name} <${./drain.sh} || echo "Could not disconnect an earlier connection"

              # connects to controller with ssh and parses the secret from the jnlp file
              JENKINS_SECRET="$(
                ssh -i ${lib.escapeShellArg cfg.controllerSshKeyFile} ${config.networking.hostName}@''${CONTROLLER#*//} \
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

  connect-script = pkgs.writeShellApplication {
    name = "connect";
    runtimeInputs = with pkgs; [
      openssh
      coreutils
      sudo
      systemd
    ];
    text = # sh
      ''
        url="''${1%/}"  # Remove trailing slash

        if [[ ! $url =~ ^https?://[^/]+$ ]]; then
          echo "ERROR: The URL should start with https and not have any subpath"
          exit 1
        fi

        if [[ ! -f /var/lib/jenkins/jenkins.env ]]; then
          # create the file with correct permissions
          sudo install -o jenkins -g jenkins -m 600 /dev/null /var/lib/jenkins/jenkins.env
        fi

        # add this controller to known hosts
        sudo -u jenkins ssh-keygen -R "''${url#*//}" 2>/dev/null || true
        sudo -u jenkins ssh -o StrictHostKeyChecking=no -i ${lib.escapeShellArg cfg.controllerSshKeyFile} "${config.networking.hostName}@''${url#*//}" exit

        echo "CONTROLLER=$url" | sudo tee /var/lib/jenkins/jenkins.env
        sudo systemctl restart start-agents.service

        echo "Connected agents to the controller"
      '';
  };

  disconnect-script = pkgs.writeShellApplication {
    name = "disconnect";
    runtimeInputs = with pkgs; [
      coreutils
      sudo
      systemd
    ];
    text = # sh
      ''
        sudo systemctl stop start-agents.service
        echo "CONTROLLER=" | sudo tee /var/lib/jenkins/jenkins.env

        echo "Disconnected agents from the controller"
      '';
  };

  # Scheduled deployment drains the agent by taking its nodes temporarily
  # offline on the controller, see ./drain.sh.
  drain = pkgs.writeShellApplication {
    name = "testagent-drain";
    runtimeInputs = with pkgs; [
      gnused
      openssh
      util-linux
    ];
    text = ''
      controller=$(sed -n 's/^CONTROLLER=//p' /var/lib/jenkins/jenkins.env 2>/dev/null || true)
      # A disconnected agent runs no jobs.
      [[ -n $controller ]] || exit 0
      runuser -u jenkins -- ssh -o BatchMode=yes -i ${lib.escapeShellArg cfg.controllerSshKeyFile} \
        "${config.networking.hostName}@''${controller#*//}" \
        bash -s -- "$1" ${
          lib.escapeShellArgs (map (device: "${cfg.nodeNamePrefix}-${device}") cfg.devices)
        } <${./drain.sh}
    '';
  };

  relayPython = pkgs.python3.withPackages (
    ps: with ps; [
      fastapi
      uvicorn
      jinja2
      python-multipart
      requests
      pyserial
    ]
  );

  relay-board-exporter = pkgs.writeScriptBin "relay-board-exporter" ''
    #!${relayPython}/bin/python3
    ${builtins.readFile ./relay_board_exporter.py}
  '';
in
{
  options.services.testagent = {
    enable = lib.mkEnableOption "the Ghaf Jenkins test agent";

    variant = lib.mkOption {
      type = lib.types.str;
      description = "Agent variant, such as dbg, dev, prod or release, used as the default prefix for Jenkins node names.";
    };

    devices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Device labels used to create Jenkins agent services.";
    };

    testConfig = lib.mkOption {
      type = lib.types.nullOr (pkgs.formats.json { }).type;
      default = null;
      description = "Contents of /etc/jenkins/test_config.json, written unchanged. Leave unset to manage the file directly.";
    };

    testCredentialFiles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.strMatching "/[^[:space:]:]+");
      default = { };
      description = ''
        Runtime Robot credential files keyed by secret name, readable by jenkins.
        Files at other paths are exposed read-only at /run/secrets/<name> inside
        each agent service. Secret provisioning remains the host's responsibility.
      '';
    };
    controllerSshKeyFile = lib.mkOption {
      type = lib.types.str;
      default = config.sops.secrets.ssh_host_ed25519_key.path;
      description = "Runtime SSH private key used to authenticate to Jenkins controllers.";
    };
    provenanceTrustPolicyFile = lib.mkOption {
      type = lib.types.path;
      default = "${self.outPath}/slsa/provenance-trust-policy.yaml";
      description = "Policy for verifying downloaded build provenance.";
    };
    nodeNamePrefix = lib.mkOption {
      type = lib.types.str;
      default = cfg.variant;
      description = "Jenkins node name prefix; must match the controller registration.";
    };
    tooling = {
      relayboard = lib.mkEnableOption "KMTronic relay-board tooling and exporter";
      jetson.enable = lib.mkOption {
        type = lib.types.bool;
        default = lib.any (label: lib.hasPrefix "orin-" label || label == "agx-64-sec-boot") cfg.devices;
        description = "Install Jetson board automation.";
      };
      brainstem.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install Acroname USB hub tools and udev rules.";
      };
      usbSdmux.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install USB SD mux tools and udev rules.";
      };
    };
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional tools available in user sessions and agent services.";
    };
  };

  # Add deployment hooks only when the host imports and enables scheduled deployment.
  imports = [
    {
      config = lib.optionalAttrs (options.services ? scheduled-deployment) (
        lib.mkIf (cfg.enable && config.services.scheduled-deployment.enable) {
          services.scheduled-deployment = {
            drain = lib.getExe drain;
            # Without a controller, the agents exit and nothing is drained. Remoting
            # logs the open WebSocket once the controller accepts the agent's secret.
            # After a reboot, the latest invocation can be from the previous boot.
            postDeployChecks = ''
              if grep -q '^CONTROLLER=.' /var/lib/jenkins/jenkins.env; then
                for unit in ${lib.concatMapStringsSep " " (device: "agent-${device}") cfg.devices}; do
                  tries=24
                  until journalctl -q -b -u "$unit" -I -g 'WebSocket connection open'; do
                    ((--tries > 0)) || { echo "$unit did not connect to the controller"; exit 1; }
                    sleep 5
                  done
                done
              fi
            '';
          };
        }
      );
    }
  ];

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

    services.udev.packages =
      lib.optional cfg.tooling.brainstem.enable self.packages.${pkgs.stdenv.hostPlatform.system}.brainstem
      ++ lib.optional cfg.tooling.usbSdmux.enable pkgs.usbsdmux;

    systemd.services =
      # map hardware to services
      builtins.listToAttrs (map (hw: lib.nameValuePair "agent-${hw}" (mkAgent hw)) cfg.devices) // {
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
                  # network-online.target can be reached before the controller
                  # resolves, because dhcpcd counts the Nebula address. Retry 30
                  # times, waiting up to 10 seconds between tries.
                  wget --retry-on-host-error --retry-connrefused --waitretry=10 --tries=30 \
                    "$CONTROLLER/jnlpJars/agent.jar" -O agent.jar
                ''
            );
          };
        };
        relay-board-metric-exporter = lib.mkIf cfg.tooling.relayboard {
          description = "KMTronic Relay Board Prometheus Exporter";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          serviceConfig = {
            Type = "simple";
            ExecStart = "${relay-board-exporter}/bin/relay-board-exporter";
            Restart = "on-failure";
            RestartSec = "5s";
          };
          path = with pkgs; [
            bash
            jq
            socat
            coreutils
            gawk
            relay-board-exporter
            inputs.robot-framework.packages.${pkgs.stdenv.hostPlatform.system}.KMTronic
          ];
        };
      };

    # packages available in all user sessions
    environment.systemPackages = [
      connect-script
      disconnect-script
    ]
    ++ agentPackages
    ++ lib.optional cfg.tooling.relayboard relay-board-exporter
    ++ (with pkgs; [
      socat
      minicom
      jq
      curl
      grafana-loki
      openssl
      (python3.withPackages (ps: with ps; [ pyserial ]))
    ]);

    environment.etc."jenkins/test_config.json" = lib.mkIf (cfg.testConfig != null) {
      text = builtins.toJSON cfg.testConfig;
    };

    environment.etc."jenkins/provenance-trust-policy.yaml".source = cfg.provenanceTrustPolicyFile;

    environment.etc."jenkins/ci-test-automation-pinned-source".text = inputs.robot-framework.outPath;
  };
}
