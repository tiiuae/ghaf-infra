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

  users.users = {
    testagent-release = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPP2xRl4jtu1ARpyj9W3uEo+GACLywosKhal432CgK+H"
      ];
    };
  };

  services.jenkins = {
    enable = true;
    listenAddress = "localhost";
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
      # Disable the intitial setup wizard, and the creation of initialAdminPassword.
      "-Djenkins.install.runSetupWizard=false"
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

        # Introduce /trigger/* api mapping them directly to jenkins /job/*
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

        @unauthenticated {
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
      oauth2_proxy_client_secret.owner = "oauth2-proxy";
      oauth2_proxy_cookie_secret.owner = "oauth2-proxy";
      jenkins_api_token.owner = "jenkins";
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
