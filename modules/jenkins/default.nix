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
  cfg = config.services.ghaf-jenkins;
  signing = cfg.signing;
  signingPackages =
    (with pkgs; [
      opensc
      openssl
    ])
    ++ (with inputs.ci-yubi.packages.${pkgs.stdenv.hostPlatform.system}; [
      uefisign
      uefisigniso
      uefisign-simple
      uefi-sign-sysupdate
    ])
    ++ (with self.packages.${pkgs.stdenv.hostPlatform.system}; [
      verify-signature
      select-pkcs11-node
      run-cosign
      systemd-sbsign
    ]);
  proxyEndpoints = signing.proxy.endpoints;
  proxyEndpointsFile = toString (
    pkgs.writeText "jenkins-pkcs11-endpoints.json" (builtins.toJSON proxyEndpoints)
  );
  proxyModule = "${
    self.packages.${pkgs.stdenv.hostPlatform.system}.pkcs11-proxy
  }/lib/libpkcs11-proxy.so";
  signingModule = if signing.proxy.enable then proxyModule else signing.modulePath;
  signingEnvironment =
    signing.extraEnvironment
    // {
      JENKINS_PKCS11_MODULE = signingModule;
      JENKINS_SIGNING_KEYS_FILE = toString (
        pkgs.writeText "jenkins-signing-keys.json" (builtins.toJSON signing.keys)
      );
      OPENSSL_CONF = toString (
        pkgs.writeText "jenkins-openssl.cnf" ''
          openssl_conf = openssl_init

          [openssl_init]
          providers = provider_sect

          [provider_sect]
          default = default_sect
          pkcs11 = pkcs11_sect

          [default_sect]
          activate = 1

          [pkcs11_sect]
          activate = 1
          module = "${pkgs.pkcs11-provider}/lib/ossl-modules/pkcs11.so"
          pkcs11-module-path = "${signingModule}"
          ${lib.optionalString (
            signing.providerQuirks != null
          ) "pkcs11-module-quirks = ${signing.providerQuirks}"}
          ${lib.optionalString (signing.pinFile != null) "pkcs11-module-token-pin = file:${signing.pinFile}"}
        ''
      );
    }
    // lib.optionalAttrs (signing.pinFile != null) {
      JENKINS_SIGNING_PIN_FILE = signing.pinFile;
    }
    // lib.optionalAttrs (signing.uefi.certificateFile != null) {
      JENKINS_UEFI_CERTIFICATE_FILE = signing.uefi.certificateFile;
    }
    // lib.optionalAttrs signing.proxy.enable {
      JENKINS_PKCS11_ENDPOINTS_FILE = proxyEndpointsFile;
      PKCS11_PROXY_MODULE = proxyModule;
      PKCS11_PROXY_SOCKET = if proxyEndpoints == [ ] then "" else (builtins.head proxyEndpoints).socket;
      PKCS11_PROXY_TLS_PSK_FILE = signing.proxy.tlsPskFile;
      PKCS11_TLS_IDENTITY = signing.proxy.identity;
    };

  remoteStoresFromBuildMachines = builtins.listToAttrs (
    map (
      builder:
      let
        sshKey = builder.sshKey or null;
        sshUser = builder.sshUser or null;
      in
      {
        name = builder.system;
        value =
          "${builder.protocol}://"
          + (if sshUser == null then "" else "${sshUser}@")
          + builder.hostName
          + (
            if sshKey == null then
              ""
            else
              "${if lib.hasInfix "?" builder.hostName then "&" else "?"}ssh-key=${sshKey}"
          );
      }
    ) config.nix.buildMachines
  );

  # copies only pipelines declared in cfg.pipelines
  filteredPipelines = pkgs.runCommand "pipelines" { } ''
    mkdir -p $out
    ${pkgs.lib.concatMapStringsSep "\n" (name: ''
      cp ${./pipelines}/${name}.groovy "$out/"
    '') cfg.pipelines}
  '';

  # Jenkins shared libraries expect a Git repository. Turn the repository-local
  # pipeline-library sources into a tiny synthetic repo and expose it as
  # /etc/jenkins/pipeline-library for the file:// retriever configured in CasC.
  pipelineSharedLibrary = pkgs.runCommand "pipeline-library" { nativeBuildInputs = [ pkgs.git ]; } ''
    mkdir -p "$out"
    cp -r ${./pipeline-library}/. "$out/"
    chmod -R u+w "$out"
    cd "$out"
    # Create a single deterministic commit so the Nix output is reproducible
    # while still looking like a normal Git repository to Jenkins.
    git init --initial-branch=main
    git add .
    GIT_AUTHOR_DATE="@''${SOURCE_DATE_EPOCH} +0000" \
    GIT_COMMITTER_DATE="@''${SOURCE_DATE_EPOCH} +0000" \
    git -c user.email=nix@example.invalid -c user.name=Nix \
      commit -m "Provision Jenkins shared library"
  '';

  cascConfig = pkgs.writeText "config.yaml" (
    # YAML is a superset of JSON, ie. json is valid yaml
    builtins.toJSON {
      unclassified.location.url = "${cfg.url}";
      jenkins.numExecutors = cfg.numExecutors;
      jenkins.nodes = # all permutations of device and host lists
        lib.mapCartesianProduct
          (
            { host, device }:
            {
              permanent = {
                name = "${host}-${device}";
                labelString = device;
                launcher = "inbound";
                mode = "EXCLUSIVE";
                remoteFS = "/var/lib/jenkins/agents/${device}";
                retentionStrategy = "always";
              };
            }
          )
          {
            host = cfg.nodes.testagentHosts;
            device = cfg.nodes.devices;
          };
    }
  );
in
{
  options.services.ghaf-jenkins = {
    enable = lib.mkEnableOption "the Ghaf Jenkins controller";
    envType = lib.mkOption {
      type = lib.types.enum [
        "dbg"
        "dev"
        "prod"
        "release"
        "vm"
      ];
      description = "Environment identifier exposed to Jenkins jobs";
    };
    url = lib.mkOption {
      type = lib.types.str;
      description = "Public URL of the jenkins instance";
    };
    registry = {
      url = lib.mkOption {
        type = lib.types.str;
        description = "OCI registry exposed to Jenkins jobs";
      };
      passwordFile = lib.mkOption {
        type = lib.types.str;
        description = "Path to the OCI registry password file";
      };
    };
    auth = {
      enable = lib.mkEnableOption "OIDC authentication and the HTTPS reverse proxy";
      domain = lib.mkOption {
        type = lib.types.str;
        description = "Public hostname of this Jenkins instance";
      };
      clientID = lib.mkOption {
        type = lib.types.str;
        description = "OIDC client ID";
      };
      oidcIssuerUrl = lib.mkOption {
        type = lib.types.str;
        description = "OIDC issuer URL";
      };
      clientSecretFile = lib.mkOption {
        type = lib.types.str;
        description = "Path to the OIDC client secret file";
      };
      cookieSecretFile = lib.mkOption {
        type = lib.types.str;
        description = "Path to the OAuth2 Proxy cookie secret file";
      };
      groups = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = { };
        description = "Jenkins permissions keyed by OIDC group name";
      };
    };
    numExecutors = lib.mkOption {
      type = lib.types.ints.positive;
      description = "Number of built-in Jenkins executors.";
      default = 12;
    };
    extraCasc = lib.mkOption {
      type = lib.types.attrs;
      description = "Extra configuration to be added into the jenkins casc";
      default = { };
    };
    pipelines = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Jenkins pipelines to load from the pipelines directory";
      default = [ ];
    };
    nodes = {
      devices = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Devices to create agent nodes for";
        default = [ ];
      };
      testagentHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Variations of device nodes to create";
        default = [ ];
      };
      authorizedKeys = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        description = "SSH public keys keyed by test-agent hostname";
        default = { };
      };
    };
    pluginsFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to the plugins.json";
      default = ./plugins.json;
    };
    integrations = {
      github = {
        enable = lib.mkEnableOption "the GitHub integration";
        tokenFile = lib.mkOption {
          type = lib.types.str;
          description = "Path to the GitHub status token file";
        };
        webhookSecretFile = lib.mkOption {
          type = lib.types.str;
          description = "Path to the GitHub webhook secret file";
        };
      };
      cachix = {
        enable = lib.mkEnableOption "the Cachix integration";
        tokenFile = lib.mkOption {
          type = lib.types.str;
          description = "Path to the Cachix authentication token file";
        };
      };
      jira = {
        enable = lib.mkEnableOption "the Jira integration";
        tokenFile = lib.mkOption {
          type = lib.types.str;
          description = "Path to the Jira API token file";
        };
      };
    };
    archive = {
      enable = lib.mkEnableOption "artifact archiving";
      s3Credentials = {
        accessKeyFile = lib.mkOption {
          type = lib.types.str;
          description = "Path to the S3 access key file";
        };
        secretKeyFile = lib.mkOption {
          type = lib.types.str;
          description = "Path to the S3 secret key file";
        };
      };
    };
    signing = {
      enable = lib.mkEnableOption "PKCS#11 signing for Jenkins";
      modulePath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to a PKCS#11 library for direct signing";
      };
      pinFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Runtime path to the PKCS#11 token PIN file";
      };
      providerQuirks = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = if signing.proxy.enable then "no-deinit" else null;
        description = "OpenSSL PKCS#11 provider quirks";
      };
      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional runtime environment for the PKCS#11 library";
      };
      keys = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = { };
        description = "Ordered PKCS#11 key URI candidates by signing purpose";
      };
      uefi.certificateFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to the public certificate used when signing UEFI images";
      };
      proxy = {
        enable = lib.mkEnableOption "the PKCS#11 signing proxy client";
        endpoints = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  description = "Endpoint name recorded in the signing result";
                };
                socket = lib.mkOption {
                  type = lib.types.str;
                  description = "PKCS#11 proxy socket URL";
                };
              };
            }
          );
          default = [ ];
          description = "Proxy endpoints in preference order";
        };
        tlsPskFile = lib.mkOption {
          type = lib.types.str;
          description = "Runtime path to the proxy TLS PSK file";
        };
        identity = lib.mkOption {
          type = lib.types.str;
          default = config.networking.hostName;
          description = "Identity presented to the PKCS#11 proxy";
        };
      };
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = lib.optionals signing.enable [
      {
        assertion = signing.proxy.enable || signing.modulePath != null;
        message = "services.ghaf-jenkins.signing.modulePath is required without the proxy";
      }
      {
        assertion = !signing.proxy.enable || signing.modulePath == null;
        message = "services.ghaf-jenkins.signing.modulePath must be unset when the proxy is enabled";
      }
      {
        assertion = !signing.proxy.enable || proxyEndpoints != [ ];
        message = "services.ghaf-jenkins.signing.proxy.endpoints must contain at least one endpoint";
      }
      {
        assertion = !(signing.keys ? uefi) || signing.uefi.certificateFile != null;
        message = "services.ghaf-jenkins.signing.uefi.certificateFile is required for a UEFI signing key";
      }
    ];
    environment.variables = lib.mkIf signing.enable signingEnvironment;
    environment.systemPackages = lib.optionals signing.enable signingPackages;
    services.jenkins = {
      enable = true;
      listenAddress = "localhost";
      port = 8081;
      withCLI = true;
      packages =
        (with pkgs; [
          bashInteractive # 'sh' step in jenkins pipeline requires this
          coreutils
          colorized-logs
          csvkit
          curl
          git
          gnutar
          hostname
          jq
          nix
          openssh
          wget
          zstd
        ])
        ++ [
          inputs.sbomnix.packages.${pkgs.stdenv.hostPlatform.system}.sbomnix # provenance
          pkgs.oras
          self.packages.${pkgs.stdenv.hostPlatform.system}.oci-publish
          self.packages.${pkgs.stdenv.hostPlatform.system}.policy-checker
          self.packages.${pkgs.stdenv.hostPlatform.system}.source-vsa
        ]
        ++ lib.optionals cfg.integrations.cachix.enable [
          pkgs.cachix
          pkgs.nixos-rebuild
        ]
        ++ lib.optionals cfg.archive.enable [
          pkgs.tree
          self.packages.${pkgs.stdenv.hostPlatform.system}.archive-ghaf-release
        ]
        ++ lib.optionals signing.enable signingPackages;

      environment = lib.optionalAttrs signing.enable signingEnvironment // {
        CI_ENV = cfg.envType;
        OCI_REGISTRY = cfg.registry.url;
        JIRA_TOKEN_AVAILABLE = lib.boolToString cfg.integrations.jira.enable;
      };

      extraJavaOptions = [
        # Useful when the 'sh' step fails:
        "-Dorg.jenkinsci.plugins.durabletask.BourneShellScript.LAUNCH_DIAGNOSTICS=true"
        # If we want to allow robot framework reports, we need to adjust Jenkins CSP:
        # https://plugins.jenkins.io/robot/#plugin-content-log-file-not-showing-properly
        "-Dhudson.model.DirectoryBrowserSupport.CSP=\"sandbox allow-scripts; default-src 'none'; img-src 'self' data: ; style-src 'self' 'unsafe-inline' data: ; script-src 'self' 'unsafe-inline' 'unsafe-eval';\""
        # Point to configuration-as-code config
        "-Dcasc.jenkins.config=/etc/jenkins/casc"
        # Disable the initial setup wizard, and the creation of initialAdminPassword.
        "-Djenkins.install.runSetupWizard=false"
        # Shared library retrieval uses file:///etc/jenkins/pipeline-library.
        "-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true"
        # Allow setting the following possibly undefined parameters
        "-Dhudson.model.ParametersAction.safeParameters=DESC,RELOAD_ONLY,GHAF_FLAKE_REF"
        # Ensure workspace root dir is what we expect
        ''-Djenkins.model.Jenkins.workspacesDir=$JENKINS_HOME/workspace/\$ITEM_FULL_NAME''
      ];
      plugins =
        let
          manifest = builtins.fromJSON (builtins.readFile cfg.pluginsFile);

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

    services.oauth2-proxy = lib.mkIf cfg.auth.enable {
      enable = true;
      inherit (cfg.auth) clientID oidcIssuerUrl;
      clientSecretFile = cfg.auth.clientSecretFile;
      cookie.secretFile = cfg.auth.cookieSecretFile;
      provider = "oidc";
      setXauthrequest = true;
      cookie.secure = true;
      extraConfig = {
        email-domain = "*";
        auth-logging = true;
        request-logging = true;
        standard-logging = true;
        reverse-proxy = true;
        scope = "openid profile email groups offline_access";
        cookie-expire = "168h";
        cookie-refresh = "24h";
        cookie-samesite = "lax";
        cookie-csrf-samesite = "lax";
        skip-provider-button = true;
        whitelist-domain = cfg.auth.domain;
      };
    };

    services.caddy = lib.mkIf cfg.auth.enable {
      enable = true;
      enableReload = false;
      configFile = pkgs.writeText "Caddyfile" ''
        {
          admin off
        }

        https://${cfg.auth.domain} {
          handle /login {
            redir * /
          }

          handle_path /artifacts* {
            root * /var/lib/jenkins/artifacts
            file_server {
              browse
            }
          }

          @unauthenticated {
            path /github-webhook /github-webhook/*
            path /jnlpJars /jnlpJars/*
            path /wsagents /wsagents/*
          }

          handle @unauthenticated {
            reverse_proxy localhost:8081
          }

          handle /oauth2/* {
            reverse_proxy localhost:4180 {
              header_up X-Real-IP {remote_host}
              header_up X-Forwarded-Uri {uri}
            }
          }

          handle {
            forward_auth localhost:4180 {
              uri /oauth2/auth
              header_up X-Real-IP {remote_host}

              copy_headers {
                X-Auth-Request-User>X-Forwarded-User
                X-Auth-Request-Groups>X-Forwarded-Groups
                X-Auth-Request-Email>X-Forwarded-Mail
                X-Auth-Request-Preferred-Username>X-Forwarded-DisplayName
              }

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

    systemd.services.oauth2-proxy = lib.mkIf cfg.auth.enable {
      serviceConfig.RestartSec = 10;
      unitConfig.StartLimitBurst = 0;
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.auth.enable [ 443 ];

    # Jenkins needs to be trusted user to use nix build --store
    nix.settings.trusted-users = [ "jenkins" ];

    # Caddy needs to be able to access files under /var/lib/jenkins/artifacts.
    # Use traverse-only access on JENKINS_HOME and scope group access to caddy.service.
    users.users = lib.mkMerge [
      (lib.mapAttrs (_: publicKey: {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ publicKey ];
      }) cfg.nodes.authorizedKeys)
      (lib.mkIf config.services.caddy.enable {
        jenkins.homeMode = "710";
      })
    ];
    systemd.services.caddy = lib.mkIf config.services.caddy.enable {
      serviceConfig.SupplementaryGroups = [ "jenkins" ];
    };

    environment.etc = lib.mkMerge [
      {
        "jenkins/nix-fast-build.sh".source = "${self.outPath}/scripts/nix-fast-build.sh";
        "jenkins/remote-stores.json".text = builtins.toJSON remoteStoresFromBuildMachines;
        "jenkins/provenance-trust-policy.yaml".source = "${self.outPath}/slsa/provenance-trust-policy.yaml";
        "jenkins/release-policy.yaml".source = "${self.outPath}/slsa/release-policy.yaml";
        "jenkins/pipelines".source = filteredPipelines;
        "jenkins/pipeline-library".source = pipelineSharedLibrary;
        "jenkins/casc/common.yaml".source = ./casc/common.yaml;
        "jenkins/casc/config.yaml".source = cascConfig;
        "jenkins/casc/extraConfig.yaml".source = pkgs.writeText "extraConfig.yaml" (
          builtins.toJSON cfg.extraCasc
        );
      }
      (lib.mkIf cfg.integrations.cachix.enable {
        "jenkins/casc/cachix.yaml".source = pkgs.replaceVars ./casc/cachix.yaml {
          secretFile = cfg.integrations.cachix.tokenFile;
        };
      })
      (lib.mkIf cfg.integrations.github.enable {
        "jenkins/casc/githubToken.yaml".source = pkgs.replaceVars ./casc/githubToken.yaml {
          secretFile = cfg.integrations.github.tokenFile;
        };
        "jenkins/casc/githubWebhook.yaml".source = pkgs.replaceVars ./casc/githubWebhook.yaml {
          secretFile = cfg.integrations.github.webhookSecretFile;
        };
      })
      (lib.mkIf cfg.archive.enable {
        "jenkins/casc/archiveArtifacts.yaml".source = pkgs.replaceVars ./casc/archiveArtifacts.yaml {
          inherit (cfg.archive.s3Credentials) accessKeyFile secretKeyFile;
        };
      })
      {
        "jenkins/casc/registryPublish.yaml".source = pkgs.replaceVars ./casc/registryPublish.yaml {
          secretFile = cfg.registry.passwordFile;
        };
      }
      (lib.mkIf cfg.integrations.jira.enable {
        "jenkins/casc/jiraToken.yaml".source = pkgs.replaceVars ./casc/jiraToken.yaml {
          secretFile = cfg.integrations.jira.tokenFile;
        };
      })
      (lib.mkIf cfg.auth.enable {
        "jenkins/casc/auth.yaml".source = pkgs.writeText "auth.yaml" (
          builtins.toJSON {
            jenkins = {
              authorizationStrategy.globalMatrix.entries = [
                {
                  group = {
                    name = "testagents";
                    permissions = [ "Agent/Connect" ];
                  };
                }
              ]
              ++ lib.mapAttrsToList (name: permissions: {
                group = { inherit name permissions; };
              }) cfg.auth.groups;
              securityRealm.reverseProxy = {
                customLogOutUrl = "/oauth2/sign_out";
                disableLdapEmailResolver = true;
                forwardedDisplayName = "X-Forwarded-DisplayName";
                forwardedEmail = "X-Forwarded-Mail";
                forwardedUser = "X-Forwarded-User";
                headerGroups = "X-Forwarded-Groups";
                headerGroupsDelimiter = ",";
                inhibitInferRootDN = false;
              };
            };
          }
        );
      })
    ];

    systemd.services.jenkins = {
      # Ensure plugins dir exists before the module-generated preStart script
      # runs `rm -r /var/lib/jenkins/plugins`, to avoid first-boot noise.
      preStart = lib.mkBefore ''
        mkdir -p /var/lib/jenkins/plugins
        mkdir -p ${config.services.jenkins.home}/userContent
        rm -f ${config.services.jenkins.home}/userContent/pipeline-graph-view-nested-layout.js
        cp ${./user-content/pipeline-graph-view-nested-layout.js} \
          ${config.services.jenkins.home}/userContent/pipeline-graph-view-nested-layout.js
        chown jenkins:jenkins \
          ${config.services.jenkins.home}/userContent/pipeline-graph-view-nested-layout.js
      '';
      serviceConfig = {
        Restart = "on-failure";
      };
    };

    # Remove all config files from jenkins home before loading the casc.
    # This ensures there's no lingering config from the past,
    # and only what is in the casc is regenerated
    systemd.services.jenkins-config-cleanup = {
      before = [ "jenkins.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "jenkins";
        WorkingDirectory = "/var/lib/jenkins";
      };
      script = # sh
        ''
          rm -f *.xml
          rm -rf nodes/*/
          rm -f jobs/*/config.xml
        '';
    };

    systemd.services.jenkins-purge-artifacts = {
      after = [ "jenkins.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "jenkins";
        WorkingDirectory = "/var/lib/jenkins";
      };
      path = with pkgs; [
        coreutils
        nix
      ];
      script = builtins.readFile ./scripts/purge-jenkins-artifacts.sh;
    };

    systemd.timers.jenkins-purge-artifacts = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "minutely";
      };
    };
  };
}
