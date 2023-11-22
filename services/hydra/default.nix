# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}: let
  # See: https://nixos.org/manual/nix/stable/advanced-topics/distributed-builds.html#remote-builds
  # Remote builder fields:
  # 1 - Remote store URI
  # 2 - Comma-separated list of builder supported platfor identifiers
  # 3 - SSH identity file used by hydra-queue-runner to log in to the remote builder
  # 4 - Max number of builds that will be executed in parallel on the machine
  # 5 - Speed factor: relative speed of the machine; nix prefers fastest builder by speed factor
  # 6 - Supported features for the remote builder
  # 7 - Mandatory features
  # 8 - The (base64-encoded) public host key of the remote machine (vs. ssh_known_hosts)
  localMachine = pkgs.writeTextFile {
    name = "build-localMachine";
    text = ''
      localhost x86_64-linux - 14 4 kvm,benchmark,big-parallel,nixos-test - -
    '';
  };
  azarmMachine = pkgs.writeTextFile {
    name = "build-azarmMachine";
    text = ''
      ssh://nix@10.0.2.10 aarch64-linux ${config.sops.secrets.id_buildfarm.path} 8 2 kvm,benchmark,big-parallel,nixos-test - -
    '';
  };
  awsarmMachine = pkgs.writeTextFile {
    name = "build-awsarmMachine";
    text = ''
      ssh://nix@awsarm.vedenemo.dev aarch64-linux ${config.sops.secrets.id_buildfarm.path} 16 4 kvm,benchmark,big-parallel,nixos-test - -
    '';
  };
  createJobsetsScript = pkgs.stdenv.mkDerivation {
    name = "create-jobsets";
    unpackPhase = ":";
    buildInputs = [pkgs.makeWrapper];
    installPhase = "install -m755 -D ${./create-jobsets.sh} $out/bin/create-jobsets";
    postFixup = ''
      wrapProgram "$out/bin/create-jobsets" \
        --prefix PATH ":" ${lib.makeBinPath [pkgs.curl]}
    '';
  };
in {
  programs.ssh.knownHosts = {
    # Add builder machines' public ids to ssh known_hosts
    azarm = {
      hostNames = ["10.0.2.10"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIuqtmsPNK6bR+OUfLjtjC3zcwMgG+ZLlWlLihDzUOF";
    };
    awsarm = {
      hostNames = ["awsarm.vedenemo.dev"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL3f7tAAO3Fc+8BqemsBQc/Yl/NmRfyhzr5SFOSKqrv0";
    };
  };
  programs.ssh.extraConfig = lib.mkAfter ''
    host awsarm.vedenemo.dev
        Hostname awsarm.vedenemo.dev
        Port 20220
  '';
  services.hydra = {
    enable = true;
    port = 3000;
    hydraURL = "http://localhost:3000";
    notificationSender = "hydra@localhost";
    useSubstitutes = true;

    buildMachinesFiles = [
      "${localMachine}"
      "${azarmMachine}"
      "${awsarmMachine}"
    ];

    extraConfig = ''
      max_output_size = ${builtins.toString (32 * 1024 * 1024 * 1024)};
    '';
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_14;
    identMap = ''
      hydra-users hydra hydra
      hydra-users hydra-queue-runner hydra
      hydra-users hydra-www hydra
      hydra-users root postgres
      hydra-users postgres postgres
    '';
  };

  # delete build logs older than 30 days
  systemd.services.hydra-delete-old-logs = {
    startAt = "Sun 05:45";
    serviceConfig.ExecStart = "${pkgs.findutils}/bin/find /var/lib/hydra/build-logs -type f -mtime +30 -delete";
  };

  # hydra setup service
  systemd.services.hydra-manual-setup = {
    description = "Hydra Manual Setup";
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    wantedBy = ["multi-user.target"];
    requires = ["hydra-init.service"];
    after = ["hydra-init.service"];
    environment = builtins.removeAttrs config.systemd.services.hydra-init.environment ["PATH"];
    path = with pkgs; [config.services.hydra.package netcat];
    script = ''
      if [ -e ~hydra/.setup-is-complete ]; then
        exit 0
      fi

      # create signing keys
      /run/current-system/sw/bin/install -d -m 551 /etc/nix/hydra
      /run/current-system/sw/bin/nix-store --generate-binary-cache-key hydra /etc/nix/hydra/secret /etc/nix/hydra/public
      /run/current-system/sw/bin/chown -R hydra:hydra /etc/nix/hydra
      /run/current-system/sw/bin/chmod 440 /etc/nix/hydra/secret
      /run/current-system/sw/bin/chmod 444 /etc/nix/hydra/public

      # create cache
      /run/current-system/sw/bin/install -d -m 755 /var/lib/hydra/cache
      /run/current-system/sw/bin/chown -R hydra-queue-runner:hydra /var/lib/hydra/cache

      # create admin user
      export HYDRA_ADMIN_PASSWORD=$(cat ${config.sops.secrets.hydra-admin-password.path})
      ${config.services.hydra.package}/bin/hydra-create-user admin --password "$HYDRA_ADMIN_PASSWORD" --role admin

      # wait for hydra service
      while ! nc -z localhost ${toString config.services.hydra.port}; do
        sleep 1
      done

      # create hydra jobsets
      ${createJobsetsScript}/bin/create-jobsets

      # done
      touch ~hydra/.setup-is-complete
    '';
  };

  nix.settings.trusted-users = ["hydra" "hydra-evaluator" "hydra-queue-runner"];
  nix.extraOptions = ''
    keep-going = true
  '';
}
