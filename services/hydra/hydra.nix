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
  localMachine = pkgs.writeTextFile {
    name = "build-localMachine";
    text = ''
      localhost x86_64-linux - 4 1 kvm,benchmark,big-parallel,nixos-test - -
    '';
  };
  build01Machine = pkgs.writeTextFile {
    name = "build-build01Machine";
    # TODO: get rid of static IP config:
    text = ''
      ssh://nix@192.168.1.107 x86_64-linux ${config.sops.secrets.id_buildfarm.path} 4 1 kvm,benchmark,big-parallel,nixos-test - -
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
    build01 = {
      # Add build01 public id to hydra host's known_hosts
      # TODO: get rid of static IP config:
      hostNames = ["192.168.1.107"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID+hx/Ff8U123lI8wMYvmVYn5M3Cv4m+XQxxNYFgJGTo";
    };
  };
  services.hydra = {
    enable = true;
    port = 3000;
    hydraURL = "http://localhost:3000";
    notificationSender = "hydra@localhost";
    useSubstitutes = true;

    buildMachinesFiles = [
      # "${localMachine}"
      "${build01Machine}"
    ];

    extraConfig = ''
      max_output_size = ${builtins.toString (32 * 1024 * 1024 * 1024)};
    '';
  };

  networking.firewall.allowedTCPPorts = [
    config.services.hydra.port
  ];

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
    environment = builtins.removeAttrs (config.systemd.services.hydra-init.environment) ["PATH"];
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
