# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  pkgs,
  inputs,
  lib,
  ...
}:
let
  # Vendored in, as brainstem isn't suitable for nixpkgs packaging upstream:
  # https://github.com/NixOS/nixpkgs/pull/313643
  brainstem = pkgs.callPackage ../../pkgs/brainstem { };
in
{
  sops.secrets =
    let
      credential = {
        sopsFile = ./credentials.yaml;
        owner = "jenkins";
      };
    in
    {
      dut-pass = credential;
      plug-login = credential;
      plug-pass = credential;
      switch-token = credential;
      switch-secret = credential;
      wifi-ssid = credential;
      wifi-password = credential;
      pi-login = credential;
      pi-pass = credential;
    };

  services.udev.packages = [
    brainstem
    pkgs.usbsdmux
  ];

  environment.systemPackages =
    [
      inputs.robot-framework.packages.${pkgs.system}.ghaf-robot
      brainstem
    ]
    ++ (with pkgs; [
      minicom
      usbsdmux
      grafana-loki
      (python3.withPackages (ps: with ps; [ pyserial ]))
    ]);

  # The Jenkins slave service is very barebones
  # it only installs java and sets up jenkins user
  services.jenkinsSlave.enable = true;

  # Jenkins needs sudo and serial rights to perform the HW tests
  users.users.jenkins.extraGroups = [
    "wheel"
    "dialout"
    "tty"
  ];

  # This server is only exposed to the internal network
  # fail2ban only causes issues here
  services.fail2ban.enable = lib.mkForce false;

  systemd.services =
    let
      # verifies that the environment file is properly configured
      # and downloads agent.jar from the controller
      jenkins-setup-script = pkgs.writeShellScript "jenkins-setup.sh" ''
        if [[ ! -f jenkins.env ]]; then
          install -m 600 /dev/null jenkins.env
          echo "CONTROLLER=" > jenkins.env
          echo "ADMIN_PASSWORD=" >> jenkins.env
          echo "Please add jenkins controller details to $(pwd)/jenkins.env"
          exit 1
        fi

        source jenkins.env

        if [[ -z "$CONTROLLER" ]]; then
          echo "Variable CONTROLLER not set in $(pwd)/jenkins.env"
          exit 1
        fi

        if [[ -z "$ADMIN_PASSWORD" ]]; then
          echo "Variable ADMIN_PASSWORD not set in $(pwd)/jenkins.env"
          exit 1
        fi

        curl -O "$CONTROLLER/jnlpJars/agent.jar"
      '';

      # Helper function to create agent services for each hardware device
      mkAgent =
        device:
        let
          # opens a websocket connection to the jenkins controller from this agent
          jenkins-connect-script = pkgs.writeShellScript "jenkins-connect.sh" ''
            JENKINS_SECRET="$(
              curl --proto =https -u admin:$ADMIN_PASSWORD \
              $CONTROLLER/computer/${device}/jenkins-agent.jnlp |
              sed "s/.*<application-desc><argument>\([a-z0-9]*\).*/\1\n/"
            )"

            mkdir -p "/var/lib/jenkins/agents/${device}"

            ${pkgs.jdk}/bin/java \
              -jar agent.jar \
              -url "$CONTROLLER" \
              -name "${device}" \
              -secret "$JENKINS_SECRET" \
              -workDir "/var/lib/jenkins/agents/${device}" \
              -webSocket
          '';
        in
        {
          # agents require the setup service to run without errors before starting
          requires = [ "setup-agents.service" ];
          wantedBy = [ "setup-agents.service" ];
          after = [ "setup-agents.service" ];

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
            ExecStart = "${jenkins-connect-script}";
          };
        };
    in
    {
      # the setup service does not start automatically or it would fail activation
      # of the system since jenkins.env is empty before manually set up
      setup-agents = {
        path = with pkgs; [ curl ];
        serviceConfig = {
          Type = "oneshot";
          User = "jenkins";
          RemainAfterExit = "yes";
          WorkingDirectory = "/var/lib/jenkins";
          ExecStart = "${jenkins-setup-script}";
        };
      };

      # one agent per unique hardware device to act as a lock
      agent-orin-agx = mkAgent "orin-agx";
      agent-orin-nx = mkAgent "orin-nx";
      agent-dell-7330 = mkAgent "dell-7330";
      agent-nuc = mkAgent "nuc";
      agent-lenovo-x1 = mkAgent "lenovo-x1";
    };
}
