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
  connect-script = pkgs.writeShellApplication {
    name = "connect";
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
        sudo -u jenkins ssh -o StrictHostKeyChecking=no -i ${config.sops.secrets.ssh_host_ed25519_key.path} "${config.networking.hostName}@''${url#*//}" exit

        echo "CONTROLLER=$url" | sudo tee /var/lib/jenkins/jenkins.env
        sudo systemctl restart start-agents.service

        echo "Connected agents to the controller"
      '';
  };

  disconnect-script = pkgs.writeShellApplication {
    name = "disconnect";
    text = # sh
      ''
        sudo systemctl stop start-agents.service
        echo "CONTROLLER=" | sudo tee /var/lib/jenkins/jenkins.env

        echo "Disconnected agents from the controller"
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
  options.services.testagent.credentialsFile = lib.mkOption {
    type = lib.types.path;
    description = "SOPS file containing shared test-agent credentials.";
  };

  imports = [
    (import ./agent.nix { inherit self inputs; })
  ];

  config = lib.mkIf cfg.enable {
    sops.secrets =
      let
        credential = {
          sopsFile = config.services.testagent.credentialsFile;
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
        # used for ssh connections
        ssh_host_ed25519_key.owner = "jenkins";
      };

    services.udev.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.brainstem
      pkgs.usbsdmux
    ];

    # packages available in all user sessions
    environment.systemPackages = [
      connect-script
      disconnect-script
    ]
    ++ lib.optional cfg.relayBoard.enable relay-board-exporter
    ++ (with self.packages.${pkgs.stdenv.hostPlatform.system}; [
      brainstem
      policy-checker
    ])
    ++ (with inputs.robot-framework.packages.${pkgs.stdenv.hostPlatform.system}; [
      ghaf-robot
      KMTronic
    ])
    ++ (with pkgs; [
      socat
      minicom
      usbsdmux
      jq
      curl
      grafana-loki
      openssl
      (python3.withPackages (ps: with ps; [ pyserial ]))
    ]);

    systemd.services.relay-board-metric-exporter = lib.mkIf cfg.relayBoard.enable {
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

    environment.etc."jenkins/provenance-trust-policy.yaml".source =
      "${self.outPath}/slsa/provenance-trust-policy.yaml";

    environment.etc."jenkins/ci-test-automation-pinned-source".text = inputs.robot-framework.outPath;
  };
}
