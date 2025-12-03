# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  pkgs,
  inputs,
  lib,
  self,
  config,
  ...
}:
let
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

  relayPython = (
    pkgs.python3.withPackages (
      ps: with ps; [
        fastapi
        uvicorn
        jinja2
        python-multipart
        requests
        pyserial
      ]
    )
  );

  relay-board-exporter = pkgs.writeScriptBin "relay-board-exporter" ''
    #!${relayPython}/bin/python3
    ${builtins.readFile ./relay_board_exporter.py}
  '';

in
{
  imports = [
    ./agent.nix
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
    self.nixosModules.service-monitoring
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
  ]);

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
      # used for ssh connections
      ssh_host_ed25519_key.owner = "jenkins";
    };

  networking.useDHCP = true;

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;
  };

  services.udev.packages = [
    self.packages.${pkgs.stdenv.hostPlatform.system}.brainstem
    pkgs.usbsdmux
  ];

  # packages available in all user sessions
  environment.systemPackages = [
    connect-script
    disconnect-script
    relay-board-exporter
  ]
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

  # This server is only exposed to the internal network
  # fail2ban only causes issues here
  services.fail2ban.enable = lib.mkForce false;

  services.monitoring = {
    metrics.enable = true;
    logs = {
      enable = true;
      lokiAddress = "https://monitoring.vedenemo.dev";
      auth.password_file = config.sops.secrets.metrics_password.path;
    };
  };

  systemd.services.relay-board-metric-exporter = {
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

  environment.etc."jenkins/GhafInfraSignECP256.pem".source =
    "${self.outPath}/keys/GhafInfraSignECP256.pem";
}
