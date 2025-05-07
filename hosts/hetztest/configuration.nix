# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  inputs,
  modulesPath,
  lib,
  ...
}:
let
  jenkins-casc = ./casc;
in
{
  imports =
    [
      ./disk-config.nix
      (modulesPath + "/profiles/qemu-guest.nix")
      inputs.disko.nixosModules.disko
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
      user-hrosten
    ]);

  # this server has been installed with 24.11
  system.stateVersion = lib.mkForce "24.11";

  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "hetztest";
    useDHCP = true;
  };

  boot = {
    # use predictable network interface names (eth0)
    kernelParams = [ "net.ifnames=0" ];
    loader.grub = {
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
  };

  environment.systemPackages = with pkgs; [
    screen
    tmux
  ];

  # Enable zramSwap: https://search.nixos.org/options?show=zramSwap.enable
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100;
  };
  # https://wiki.archlinux.org/title/Zram#Optimizing_swap_on_zram:
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
    "vm.page-cluster" = 0;
  };

  # Increase the maximum number of open files user limit, see ulimit -n
  security.pam.loginLimits = [
    {
      domain = "*";
      item = "nofile";
      type = "-";
      value = "8192";
    }
  ];
  systemd.user.extraConfig = "DefaultLimitNOFILE=8192";

  services.jenkins = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 8081;
    withCLI = true;
    packages = with pkgs; [
      bashInteractive # 'sh' step in jenkins pipeline requires this
      coreutils
      git
      nix
      openssh
    ];
    extraJavaOptions = [
      # Useful when the 'sh' step fails:
      "-Dorg.jenkinsci.plugins.durabletask.BourneShellScript.LAUNCH_DIAGNOSTICS=true"
      # Point to configuration-as-code config
      "-Dcasc.jenkins.config=${jenkins-casc}"
    ];
    plugins =
      let
        manifest = builtins.fromJSON (builtins.readFile ./plugins.json);

        mkJenkinsPlugin =
          {
            name,
            version,
            url,
            sha256,
          }:
          lib.nameValuePair name (
            pkgs.stdenv.mkDerivation {
              inherit name version;
              src = pkgs.fetchurl {
                inherit url sha256;
              };
              phases = "installPhase";
              installPhase = "cp \$src \$out";
            }
          );
      in
      builtins.listToAttrs (map mkJenkinsPlugin manifest);
  };

  systemd.services.jenkins = {
    # Make `jenkins-cli` available
    path = with pkgs; [ jenkins ];
    # Implicit URL parameter for `jenkins-cli`
    environment = {
      JENKINS_URL = "http://localhost:8081";
    };
    postStart =
      let
        jenkins-auth = "-auth admin:\"$(cat /var/lib/jenkins/secrets/initialAdminPassword)\"";
        # Disable setup wizard and restart
        jenkins-init = pkgs.writeText "groovy" ''
          #!groovy
          import jenkins.model.*
          import jenkins.install.*
          Jenkins.getInstance().setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
          Jenkins.getInstance().save()
          Jenkins.getInstance().restart()
        '';
        # Trigger all pipelines
        jenkins-trigger-all = pkgs.writeText "groovy" ''
          #!groovy
          import jenkins.model.*
          import hudson.model.*
          for (job in Jenkins.getInstance().getAllItems(Job)) {
            println("Triggering job: " + job.getName())
            job.scheduleBuild(0);
          }
        '';
      in
      ''
        echo "Waiting jenkins to become online"
        until jenkins-cli ${jenkins-auth} who-am-i >/dev/null 2>&1; do sleep 1; done
        echo "Disable setup wizard and restart jenkins"
        jenkins-cli ${jenkins-auth} groovy = < ${jenkins-init}
        echo "Waiting jenkins to shutdown"
        until ! jenkins-cli ${jenkins-auth} who-am-i >/dev/null 2>&1; do sleep 1; done
        echo "Waiting jenkins to restart"
        until jenkins-cli ${jenkins-auth} who-am-i >/dev/null 2>&1; do sleep 1; done
        echo "Triggering jenkins jobs"
        jenkins-cli ${jenkins-auth} groovy = < ${jenkins-trigger-all}
      '';
    serviceConfig = {
      Restart = "on-failure";
    };
  };
  environment.etc."jenkins/pipelines".source = ./casc/pipelines;

  services.caddy = {
    enable = true;
    enableReload = false;
    configFile = pkgs.writeText "Caddyfile" ''
      # Disable the admin API, we don't want to reconfigure Caddy at runtime.
      {
        admin off
      }

      https://hetztest.vedenemo.dev {
        handle {
          reverse_proxy localhost:8081
        }
      }
    '';
  };

  # Expose the HTTP[S] port. We still need HTTP for the HTTP-01 challenge.
  # While TLS-ALPN-01 could be used, disabling HTTP-01 seems only possible from
  # the JSON config, which won't work alongside Caddyfile.
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
