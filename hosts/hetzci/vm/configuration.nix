# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  inputs,
  modulesPath,
  lib,
  config,
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
      inputs.sops-nix.nixosModules.sops
    ]
    ++ (with self.nixosModules; [
      common
      service-openssh
      team-devenv
    ]);

  # this server has been installed with 24.11
  system.stateVersion = lib.mkForce "24.11";

  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "hetzci-vm";
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

  # Enable early out-of-memory killing.
  # Make nix builds more likely to be killed over more important services.
  services.earlyoom = {
    enable = true;
    # earlyoom sends SIGTERM once below 5% and SIGKILL when below half
    # of freeMemThreshold
    freeMemThreshold = 5;
    extraArgs = [
      "--prefer"
      "^(nix-daemon)$"
      "--avoid"
      "^(java|jenkins-.*|sshd|systemd|systemd-.*)$"
    ];
  };
  # Tell the Nix evaluator to garbage collect more aggressively
  environment.variables.GC_INITIAL_HEAP_SIZE = "1M";
  # Always overcommit: pretend there is always enough memory
  # until it actually runs out
  boot.kernel.sysctl."vm.overcommit_memory" = "1";

  users.users = {
    testagent-dev = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDVZVd2ZBBHBYCJVOhjhfVXi4lrVYtcH5CkQjTqBfg/4 root@nixos"
      ];
    };
    testagent-prod = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILXYn8XEtZ/LoRBnM/GwNJMg0gcpFMEYEyQX3X9DTENx root@nixos"
      ];
    };
    testagent-release = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPP2xRl4jtu1ARpyj9W3uEo+GACLywosKhal432CgK+H mytarget"
      ];
    };
    testagent-uae-dev = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHO30maPQbVUqURaur8ze2S0vrrUivj2QdItIHsK75RS root@fayad-X1-testagent"
      ];
    };
  };

  systemd.services.populate-builder-machines = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
    };
    script = ''
      mkdir -p /etc/nix
      echo "ssh://hetz86-1.vedenemo.dev x86_64-linux - 20 10 kvm,nixos-test,benchmark,big-parallel" >/etc/nix/machines
      echo "ssh://hetzarm.vedenemo.dev aarch64-linux - 20 10 kvm,nixos-test,benchmark,big-parallel" >>/etc/nix/machines
    '';
  };

  nix.extraOptions = ''
    connect-timeout = 5
    system-features = nixos-test benchmark big-parallel kvm
    builders = @/etc/nix/machines
    max-jobs = 0
    trusted-public-keys = ghaf-dev.cachix.org-1:S3M8x3no8LFQPBfHw1jl6nmP8A7cVWKntoMKN3IsEQY= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
    substituters = https://ghaf-dev.cachix.org https://cache.nixos.org
    builders-use-substitutes = true
  '';

  programs.ssh = {
    # Known builder host public keys, these go to /root/.ssh/known_hosts
    knownHosts."hetz86-1.vedenemo.dev".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG05U1SHacBIrp3dH7g5O1k8pct/QVwHfuW/TkBYxLnp";
    knownHosts."hetzarm.vedenemo.dev".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILx4zU4gIkTY/1oKEOkf9gTJChdx/jR3lDgZ7p/c7LEK";

    # Custom options to /etc/ssh/ssh_config
    extraConfig = lib.mkAfter ''
      Host hetz86-1.vedenemo.dev
      Hostname hetz86-1.vedenemo.dev
      User remote-build
      IdentityFile /run/secrets/vedenemo_builder_ssh_key

      Host hetzarm.vedenemo.dev
      Hostname hetzarm.vedenemo.dev
      User remote-build
      IdentityFile /run/secrets/vedenemo_builder_ssh_key
    '';
  };

  services.jenkins = {
    enable = true;
    listenAddress = "localhost";
    port = 8081;
    withCLI = true;
    packages = with pkgs; [
      bashInteractive # 'sh' step in jenkins pipeline requires this
      coreutils
      colorized-logs
      csvkit
      curl
      git
      jq
      nix
      openssh
      wget
      zstd
    ];
    extraJavaOptions = [
      # Useful when the 'sh' step fails:
      "-Dorg.jenkinsci.plugins.durabletask.BourneShellScript.LAUNCH_DIAGNOSTICS=true"
      # Point to configuration-as-code config
      "-Dcasc.jenkins.config=${jenkins-casc}"
      # Disable the intitial setup wizard, and the creation of initialAdminPassword.
      "-Djenkins.install.runSetupWizard=false"
      # Allow setting the following possibly undefined parameters
      "-Dhudson.model.ParametersAction.safeParameters=DESC,RELOAD_ONLY"
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
  # Jenkins home dir (by default at /var/lib/jenkins) mode needs to be 755
  users.users.jenkins.homeMode = "755";

  systemd.services.jenkins = {
    serviceConfig = {
      Restart = "on-failure";
    };
  };
  environment.etc."jenkins/pipelines".source = ./casc/pipelines;
  environment.etc."jenkins/nix-fast-build.sh".source = "${self.outPath}/scripts/nix-fast-build.sh";

  services.caddy = {
    enable = true;
    enableReload = false;
    # Stub Caddy config for the hetzci-vm
    configFile = pkgs.writeText "Caddyfile" ''
      {
        admin off
        debug
        auto_https off
      }

      http://localhost, http://127.0.0.1 {

        # Route /artifacts requests to caddy file_server
        handle_path /artifacts* {
          root * /var/lib/jenkins/artifacts
          file_server {
            browse
          }
        }

        handle {
          reverse_proxy localhost:8081
        }
      }
    '';
  };

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      vedenemo_builder_ssh_key.owner = "root";
      oauth2_proxy_client_secret.owner = "oauth2-proxy";
      oauth2_proxy_cookie_secret.owner = "oauth2-proxy";
      jenkins_api_token.owner = "jenkins";
      jenkins_github_webhook_secret.owner = "jenkins";
      jenkins_github_commit_status_token.owner = "jenkins";
    };
    templates.oauth2_proxy_env = {
      content = ''
        OAUTH2_PROXY_COOKIE_SECRET=${config.sops.placeholder.oauth2_proxy_cookie_secret}
      '';
      owner = "oauth2-proxy";
    };
  };

  services.oauth2-proxy = {
    enable = true;
    clientID = "hetzci-vm";
    clientSecret = null;
    cookie.secret = null;
    provider = "oidc";
    oidcIssuerUrl = "https://auth.vedenemo.dev";
    setXauthrequest = true;
    cookie.secure = false;
    extraConfig = {
      email-domain = "*";
      auth-logging = true;
      request-logging = true;
      standard-logging = true;
      reverse-proxy = true;
      scope = "openid profile email groups";
      provider-display-name = "Vedenemo Auth";
      custom-sign-in-logo = "-";
      client-secret-file = config.sops.secrets.oauth2_proxy_client_secret.path;
    };
    keyFile = config.sops.templates.oauth2_proxy_env.path;
  };

  systemd.services.jenkins-purge-artifacts = {
    after = [ "jenkins.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "jenkins";
      WorkingDirectory = "/var/lib/jenkins";
    };
    script = builtins.readFile ./purge-jenkins-artifacts.sh;
  };
  systemd.timers.jenkins-purge-artifacts = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
    };
  };

  # Expose the HTTP[S] port. We still need HTTP for the HTTP-01 challenge.
  # While TLS-ALPN-01 could be used, disabling HTTP-01 seems only possible from
  # the JSON config, which won't work alongside Caddyfile.
  networking.firewall.allowedTCPPorts = [
    80
  ];

  # VM specific configuration:
  virtualisation.vmVariant = {
    virtualisation.sharedDirectories.shr = {
      source = "$HOME/.config/vmshared/hetzci-vm";
      target = "/shared";
    };
  };

}
