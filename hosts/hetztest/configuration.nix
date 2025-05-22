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
    testagent-release = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPP2xRl4jtu1ARpyj9W3uEo+GACLywosKhal432CgK+H"
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
      echo "ssh://build2.vedenemo.dev x86_64-linux - 20 10 kvm,nixos-test,benchmark,big-parallel" >/etc/nix/machines
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
    knownHosts."build1.vedenemo.dev".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILrcs+NiYzO14n5FystgcN5WJSLeBc+BR67vGs2cwY7d";
    knownHosts."build2.vedenemo.dev".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILL40b7SbAcL1MK3D5U9IgVRR87myFLTzVdryQnVqb7p";
    knownHosts."hetzarm.vedenemo.dev".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILx4zU4gIkTY/1oKEOkf9gTJChdx/jR3lDgZ7p/c7LEK";

    # Custom options to /etc/ssh/ssh_config
    extraConfig = lib.mkAfter ''
      Host build1.vedenemo.dev
      Hostname build1.vedenemo.dev
      User remote-build
      IdentityFile /run/secrets/vedenemo_builder_ssh_key

      Host build2.vedenemo.dev
      Hostname build2.vedenemo.dev
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
    configFile = pkgs.writeText "Caddyfile" ''
      # Disable the admin API, we don't want to reconfigure Caddy at runtime.
      {
        admin off
      }

      https://hetztest.vedenemo.dev {

        # Introduce /trigger/* api mapping requests directly to jenkins /job/*
        # letting jenkins handle the authentication for /trigger/* paths.
        # This makes it possible to authenticate with jenkins api token for
        # requests on /trigger/* endpoints.
        handle_path /trigger/* {
          rewrite * /job{uri}
          reverse_proxy localhost:8081
        }
        handle /login {
          redir * /
        }

        # Route /artifacts requests to caddy file_server
        handle_path /artifacts* {
          root * /var/lib/jenkins/artifacts
          file_server {
            browse
          }
        }

        @unauthenticated {
          # github sends webhook triggers here
          path /github-webhook /github-webhook/*

          # testagents need these
          path /jnlpJars /jnlpJars/*
          path /wsagents /wsagents/*
        }

        handle @unauthenticated {
          reverse_proxy localhost:8081
        }

        # Proxy all other requests to jenkins as-is, but delegate auth to
        # oauth2-proxy.
        # Also see https://oauth2-proxy.github.io/oauth2-proxy/configuration/integration#configuring-for-use-with-the-caddy-v2-forward_auth-directive

        handle /oauth2/* {
          reverse_proxy localhost:4180 {
            # oauth2-proxy requires the X-Real-IP and X-Forwarded-{Proto,Host,Uri} headers.
            # The reverse_proxy directive automatically sets X-Forwarded-{For,Proto,Host} headers.
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-Uri {uri}
          }
        }

        handle {
          forward_auth localhost:4180 {
            uri /oauth2/auth

            # oauth2-proxy requires the X-Real-IP and X-Forwarded-{Proto,Host,Uri} headers.
            # The forward_auth directive automatically sets the X-Forwarded-{For,Proto,Host,Method,Uri} headers.
            header_up X-Real-IP {remote_host}

            copy_headers {
              X-Auth-Request-User>X-Forwarded-User
              X-Auth-Request-Groups>X-Forwarded-Groups
              X-Auth-Request-Email>X-Forwarded-Mail
              X-Auth-Request-Preferred-Username>X-Forwarded-DisplayName
            }

            # If oauth2-proxy returns a 401 status, redirect the client to the sign-in page.
            @error status 401
            handle_response @error {
              redir * /oauth2/sign_in?rd={scheme}://{host}{uri}
            }
          }
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
    clientID = "hetztest";
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

  # Expose the HTTP[S] port. We still need HTTP for the HTTP-01 challenge.
  # While TLS-ALPN-01 could be used, disabling HTTP-01 seems only possible from
  # the JSON config, which won't work alongside Caddyfile.
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
