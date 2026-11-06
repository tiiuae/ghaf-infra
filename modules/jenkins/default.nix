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
  registeredAgents = lib.filterAttrs (_: agent: agent.enable) cfg.agents;
  # Interchangeable agents may share a logical Jenkins node. Collapse identical
  # definitions while the assertion below still rejects conflicting definitions.
  registeredNodes = lib.unique (
    lib.concatLists (
      lib.mapAttrsToList (
        _: agent:
        map (device: {
          permanent = {
            name = "${agent.nodeNamePrefix}-${device}";
            labelString = "${device} ${agent.variant}-${device}";
            launcher = "inbound";
            mode = "EXCLUSIVE";
            remoteFS = "/var/lib/jenkins/agents/${device}";
            retentionStrategy = "always";
          };
        }) agent.devices
      ) registeredAgents
    )
  );
  agentKeys = lib.mapAttrs' (
    _: agent: lib.nameValuePair agent.hostName agent.publicKey
  ) registeredAgents;
  secureAbPublicTrust =
    pkgs.runCommand "secure-ab-public-trust" { nativeBuildInputs = [ pkgs.openssl ]; }
      ''
        mkdir -p "$out"
        openssl x509 -in ${lib.escapeShellArg cfg.signing.certificates.uefi.pk} -out "$out/PK.crt"
        openssl x509 -in ${lib.escapeShellArg cfg.signing.certificates.uefi.kek} -out "$out/KEK.crt"
        openssl x509 -in ${lib.escapeShellArg cfg.signing.certificates.uefi.db} -out "$out/db.crt"
        openssl x509 -in ${lib.escapeShellArg cfg.signing.certificates.ota} -pubkey -noout > update.pem
        openssl pkey -pubin -in update.pem -outform DER -out update.der
        # Ed25519 SubjectPublicKeyInfo: fixed 12-byte header followed by the raw key.
        test "$(od -An -tx1 -N12 update.der | tr -d ' \n')" = 302a300506032b6570032100
        test "$(wc -c < update.der)" -eq 44
        tail -c 32 update.der > "$out/update.pub"
      '';
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
  proxyModule = "${
    self.packages.${pkgs.stdenv.hostPlatform.system}.pkcs11-proxy
  }/lib/libpkcs11-proxy.so";
  signingModule = if cfg.signing.proxy.enable then proxyModule else cfg.signing.modulePath;
  signingEnvironment =
    cfg.signing.extraEnvironment
    // {
      JENKINS_PKCS11_MODULE = signingModule;
      JENKINS_SIGNING_KEYS_FILE = toString (
        pkgs.writeText "jenkins-signing-keys.json" (builtins.toJSON cfg.signing.keys)
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
            cfg.signing.providerQuirks != null
          ) "pkcs11-module-quirks = ${cfg.signing.providerQuirks}"}
          ${lib.optionalString (
            cfg.signing.pinFile != null
          ) "pkcs11-module-token-pin = file:${cfg.signing.pinFile}"}
        ''
      );
    }
    // lib.optionalAttrs (cfg.signing.pinFile != null) {
      JENKINS_SIGNING_PIN_FILE = cfg.signing.pinFile;
    }
    // lib.optionalAttrs (cfg.signing.certificates.uefi.db != null) {
      JENKINS_UEFI_CERTIFICATE_FILE = cfg.signing.certificates.uefi.db;
    }
    // lib.optionalAttrs (cfg.signing.certificates.ota != null) {
      JENKINS_SECURE_AB_TRUST_DIR = toString secureAbPublicTrust;
    }
    // lib.optionalAttrs cfg.signing.proxy.enable {
      JENKINS_PKCS11_ENDPOINTS_FILE = toString (
        pkgs.writeText "jenkins-pkcs11-endpoints.json" (builtins.toJSON cfg.signing.proxy.endpoints)
      );
      PKCS11_PROXY_MODULE = proxyModule;
      PKCS11_PROXY_SOCKET =
        if cfg.signing.proxy.endpoints == [ ] then
          ""
        else
          (builtins.head cfg.signing.proxy.endpoints).socket;
      PKCS11_PROXY_TLS_PSK_FILE = cfg.signing.proxy.tlsPskFile;
      PKCS11_TLS_IDENTITY = cfg.signing.proxy.identity;
    };

  artifactsHandler = ''
    handle_path /artifacts* {
      root * /var/lib/jenkins/artifacts
      file_server {
        browse
      }
    }
  '';

  # Copy the pipeline scripts declared in jobs.
  filteredPipelines = pkgs.runCommand "pipelines" { } ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (_: job: ''
        cp "${job.scriptFile}" "$out/${job.name}.groovy"
      '') cfg.jobs
    )}
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

  cascConfig = {
    unclassified.location.url = "${cfg.url}";
    jenkins.numExecutors = cfg.numExecutors;
    jenkins.nodes = registeredNodes;
  };
in
{
  imports = [
    ../git-credentials.nix
    ./scheduled-deployment.nix
  ];

  options.services.ghaf-jenkins = {
    enable = lib.mkEnableOption "the Ghaf Jenkins controller";
    sourceVsa = {
      trustedBranch = lib.mkOption {
        type = lib.types.str;
        default = "refs/heads/main";
        description = ''
          Trusted source branch ref for Source VSA verification. Must match
          the source-ref input in the Ghaf caller workflow.
        '';
      };
      trustedWorkflowSha = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          Approved ghaf-infra commit for the Source VSA reusable workflow.
          Must match the Ghaf caller's workflow pin.
        '';
      };
    };
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
    provenanceRepository = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/tiiuae/ghaf-infra";
      description = "Infrastructure configuration repository recorded as workflow.repository in build provenance.";
    };
    remoteStores = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        x86_64-linux = "ssh-ng://remote-build@builder.example.org?ssh-key=/run/secrets/builder-key";
      };
      description = ''
        Nix build store URIs keyed by target system. Targets without an entry
        use normal nix build behavior, including any nix.buildMachines.
      '';
    };
    registry = {
      enable = lib.mkEnableOption "OCI registry publishing";
      namespace = lib.mkOption {
        type = lib.types.str;
        default = "ghaf";
        description = "OCI repository namespace. Images are published under <namespace>/<job-name>/<target>, using the job name unchanged.";
      };
      url = lib.mkOption {
        type = lib.types.str;
        description = "OCI registry exposed to Jenkins jobs";
      };
      passwordFile = lib.mkOption {
        type = lib.types.str;
        description = "Path to the OCI registry password file";
      };
    };
    artifacts.requireAuth = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Require OIDC authentication for artifact downloads and directory listings. Requires auth.enable.";
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
    jobs = lib.mkOption {
      default = { };
      description = "Pipeline jobs; keys select bundled scripts and default Jenkins names.";
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }: {
            options = {
              name = lib.mkOption {
                type = lib.types.strMatching "[A-Za-z0-9_.-]+";
                default = name;
                description = "Jenkins job name; the attribute key still selects the default bundled pipeline.";
              };
              scriptFile = lib.mkOption {
                type = lib.types.path;
                default = ./pipelines + "/${name}.groovy";
                description = "Pipeline script; defaults to the bundled pipeline selected by the job's attribute key.";
              };
              description = lib.mkOption {
                type = lib.types.str;
                default = "";
              };
              parameterDefaults = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
                description = "Default CI_TEST_REPO_URL, CI_TEST_REPO_BRANCH, DEVICE_TAG and TESTAGENT_HOST values for bundled hardware-test jobs.";
              };
              reloadOnStartup = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Invoke this job with RELOAD_ONLY=true after Jenkins starts. The script must handle this parameter without building.";
              };
            };
          }
        )
      );
    };
    agents = lib.mkOption {
      default = { };
      description = "Agent registrations, each with its own devices and SSH identity.";
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, config, ... }: {
            options = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
              };
              hostName = lib.mkOption {
                type = lib.types.strMatching "[a-z_][a-z0-9_-]*";
                default = name;
              };
              publicKey = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
              };
              variant = lib.mkOption {
                type = lib.types.strMatching "[A-Za-z0-9_.-]+";
              };
              devices = lib.mkOption {
                type = lib.types.listOf (lib.types.strMatching "[A-Za-z0-9_.-]+");
              };
              nodeNamePrefix = lib.mkOption {
                type = lib.types.strMatching "[A-Za-z0-9_.-]+";
                default = config.variant;
                description = "Match services.testagent.nodeNamePrefix. Use a unique prefix for agents sharing a variant and device label.";
              };
            };
          }
        )
      );
    };
    pluginsFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to the plugins.json";
      default = ./plugins.json;
    };
    provenanceTrustPolicyFile = lib.mkOption {
      type = lib.types.path;
      description = "Consumer-supplied policy file used to validate build provenance";
    };
    releasePolicyFile = lib.mkOption {
      type = lib.types.path;
      description = "Consumer-supplied policy file used to validate release attestations";
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
        default = if cfg.signing.proxy.enable then "no-deinit" else null;
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
      certificates = {
        uefi = {
          db = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Path to the public db certificate used when signing UEFI images";
          };
          pk = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Path to the public UEFI PK certificate included in secure A/B build trust";
          };
          kek = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Path to the public UEFI KEK certificate included in secure A/B build trust";
          };
        };
        ota = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Path to the public Ed25519 OTA certificate; setting it generates secure A/B build trust from this and the UEFI certificates";
        };
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
    assertions = [
      {
        assertion =
          let
            names = map (job: job.name) (lib.attrValues cfg.jobs);
          in
          lib.length names == lib.length (lib.unique names);
        message = "Jenkins job names must be unique.";
      }
      {
        assertion = lib.all (agent: agent.publicKey != null && agent.publicKey != "") (
          lib.attrValues registeredAgents
        );
        message = "Enabled services.ghaf-jenkins.agents require a publicKey.";
      }
      {
        assertion =
          lib.length (lib.attrNames registeredAgents)
          == lib.length (lib.unique (map (a: a.hostName) (lib.attrValues registeredAgents)));
        message = "Jenkins agent SSH hostName values must be unique.";
      }
      {
        assertion =
          let
            names = map (node: node.permanent.name) registeredNodes;
          in
          lib.length names == lib.length (lib.unique names);
        message = "Jenkins node names must be unique; set matching unique nodeNamePrefix values on overlapping agents and their registrations.";
      }
      {
        assertion = !cfg.artifacts.requireAuth || cfg.auth.enable;
        message = "services.ghaf-jenkins.artifacts.requireAuth requires auth.enable";
      }
    ]
    ++ lib.optionals cfg.signing.enable [
      {
        assertion = cfg.signing.proxy.enable || cfg.signing.modulePath != null;
        message = "services.ghaf-jenkins.signing.modulePath is required without the proxy";
      }
      {
        assertion = !cfg.signing.proxy.enable || cfg.signing.modulePath == null;
        message = "services.ghaf-jenkins.signing.modulePath must be unset when the proxy is enabled";
      }
      {
        assertion = !cfg.signing.proxy.enable || cfg.signing.proxy.endpoints != [ ];
        message = "services.ghaf-jenkins.signing.proxy.endpoints must contain at least one endpoint";
      }
      {
        assertion = !(cfg.signing.keys ? uefi) || cfg.signing.certificates.uefi.db != null;
        message = "services.ghaf-jenkins.signing.certificates.uefi.db is required for a UEFI signing key";
      }
      {
        assertion =
          cfg.signing.certificates.ota == null
          || (
            cfg.signing.certificates.uefi.pk != null
            && cfg.signing.certificates.uefi.kek != null
            && cfg.signing.certificates.uefi.db != null
          );
        message = "services.ghaf-jenkins.signing.certificates.ota requires certificates.uefi.pk, certificates.uefi.kek and certificates.uefi.db";
      }
    ];
    environment.variables = lib.mkIf cfg.signing.enable signingEnvironment;
    environment.systemPackages = [ pkgs.curl ] ++ lib.optionals cfg.signing.enable signingPackages;
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
        ++ lib.optionals cfg.signing.enable signingPackages;

      environment =
        lib.optionalAttrs cfg.signing.enable signingEnvironment
        // {
          CI_ENV = cfg.envType;
          JENKINS_HW_TEST_JOB = cfg.jobs.ghaf-hw-test.name or "ghaf-hw-test";
          JENKINS_HW_TEST_MANUAL_JOB = cfg.jobs.ghaf-hw-test-manual.name or "ghaf-hw-test-manual";
          JENKINS_RELEASE_CANDIDATE_JOB = cfg.jobs.ghaf-release-candidate.name or "ghaf-release-candidate";
          JENKINS_PROVENANCE_REPOSITORY = cfg.provenanceRepository;
          OCI_PUBLISH_ENABLED = lib.boolToString cfg.registry.enable;
          JENKINS_SIGNING_ENABLED = lib.boolToString cfg.signing.enable;
          JIRA_TOKEN_AVAILABLE = lib.boolToString cfg.integrations.jira.enable;
          SOURCE_VSA_ISSUER_SHA = cfg.sourceVsa.trustedWorkflowSha;
          SOURCE_VSA_SOURCE_REF = cfg.sourceVsa.trustedBranch;
        }
        // lib.optionalAttrs cfg.registry.enable {
          OCI_REGISTRY = cfg.registry.url;
          OCI_NAMESPACE = cfg.registry.namespace;
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

          ${lib.optionalString (!cfg.artifacts.requireAuth) artifactsHandler}

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
            route {
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
              ${lib.optionalString cfg.artifacts.requireAuth artifactsHandler}
              reverse_proxy localhost:8081
            }
          }
        }
      '';
    };

    systemd.services.oauth2-proxy = lib.mkIf cfg.auth.enable {
      serviceConfig.RestartSec = 10;
      unitConfig.StartLimitBurst = 0;
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.auth.enable [
      80
      443
    ];

    # Jenkins needs to be trusted user to use nix build --store
    nix.settings.trusted-users = [ "jenkins" ];

    # Caddy needs to be able to access files under /var/lib/jenkins/artifacts.
    # Use traverse-only access on JENKINS_HOME and scope group access to caddy.service.
    users.users = lib.mkMerge [
      (lib.mapAttrs (_: publicKey: {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ publicKey ];
      }) agentKeys)
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
        "jenkins/remote-stores.json".text = builtins.toJSON cfg.remoteStores;
        "jenkins/jobs.json".text = builtins.toJSON (
          lib.mapAttrs' (_: job: lib.nameValuePair job.name job) cfg.jobs
        );
        "jenkins/test-agent-choices.json".text = builtins.toJSON {
          devices = lib.unique (lib.concatMap (agent: agent.devices) (lib.attrValues registeredAgents));
          hosts = lib.unique (
            map (agent: agent.variant) (
              lib.filter (agent: agent.devices != [ ]) (lib.attrValues registeredAgents)
            )
          );
        };
        "jenkins/provenance-trust-policy.yaml".source = cfg.provenanceTrustPolicyFile;
        "jenkins/release-policy.yaml".source = cfg.releasePolicyFile;
        "jenkins/pipelines".source = filteredPipelines;
        "jenkins/pipeline-library".source = pipelineSharedLibrary;
        "jenkins/casc/common.yaml".source = ./casc/common.yaml;
        "jenkins/casc/config.yaml".text = builtins.toJSON cascConfig;
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
      (lib.mkIf cfg.registry.enable {
        "jenkins/casc/registryPublish.yaml".source = pkgs.replaceVars ./casc/registryPublish.yaml {
          secretFile = cfg.registry.passwordFile;
        };
      })
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
                    # Agent/Disconnect lets scheduled deployment take an
                    # agent's nodes temporarily offline.
                    permissions = [
                      # Required to fetch the agent secret from Jenkins.
                      "Overall/Read"
                      "Agent/Connect"
                      "Agent/Disconnect"
                    ];
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
