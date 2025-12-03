# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  inputs,
  lib,
  self,
  ...
}:
let
  # patch in the 1.1 update.
  # can be removed when we update to 25.11
  # https://github.com/NixOS/nixpkgs/pull/444707
  pkcs11-provider = pkgs.pkcs11-provider.overrideAttrs rec {
    version = "1.1";

    src = pkgs.fetchFromGitHub {
      owner = "latchset";
      repo = "pkcs11-provider";
      tag = "v${version}";
      fetchSubmodules = true;
      hash = "sha256-QXEwDl6pk8G5ba8lD4uYw2QuD3qS/sgd1od8crHct2s=";
    };
  };

  inherit (self.packages.${pkgs.stdenv.hostPlatform.system})
    pkcs11-proxy
    systemd-sbsign
    nethsm-pkcs11
    nethsm-exporter
    ;

  pkcs11Modules = {
    nethsm = "${nethsm-pkcs11}/lib/libnethsm_pkcs11.so";
    yubihsm = "${pkgs.yubihsm-shell}/lib/pkcs11/yubihsm_pkcs11.so";
    p11-kit = "${pkgs.p11-kit}/lib/p11-kit-proxy.so";
  };

  nethsm-operator-username = "ghafinfrasign~ghafsigner";

  nethsm-cmd = pkgs.writeShellScriptBin "nethsm-cmd" ''
    nitropy nethsm --no-verify-tls \
      --host ${config.nethsm.host} \
      --username ${nethsm-operator-username} \
      --password "$(cat ${config.sops.secrets.nethsm-operator-password.path})" \
      "$@"
  '';

  get-secureboot-keys = pkgs.writeShellScriptBin "get-secureboot-keys" ''
    set -eo pipefail

    if [[ -z "$1" ]]; then
      echo "Usage: $(basename "$0") <outpath>"
      exit 1
    fi

    # change these when rotating keys
    PK="tempPKkey"
    KEK="tempKEKkey"
    DB="tempDBkey"

    OUT="$1"
    mkdir -p "$OUT"
    pushd "$OUT"

    echo "Fetching certificates..."
    nethsm-cmd get-certificate --key-id "$PK" > PK.crt
    nethsm-cmd get-certificate --key-id "$KEK" > KEK.crt
    nethsm-cmd get-certificate --key-id "$DB" > db.crt

    echo "Creating DER files..."
    openssl x509 -in PK.crt -outform DER -out PK.der
    openssl x509 -in KEK.crt -outform DER -out KEK.der
    openssl x509 -in db.crt -outform DER -out db.der

    echo "Signing auth files..."
    OPENSSL_CONF=$OPENSSL_CONF_LEGACY_ENGINE
    cert-to-auth \
      --pk PK.crt --kek KEK.crt --db db.crt \
      --pk-uri "pkcs11:token=NetHSM;object=$PK" \
      --kek-uri "pkcs11:token=NetHSM;object=$KEK" \

    echo "Generated $(date -u) from NetHSM objects \`$PK\`, \`$KEK\` and \`$DB\`" > README.md
    echo "Done"
  '';
in
{
  options = {
    nethsm = {
      host = lib.mkOption {
        type = lib.types.str;
      };
      logging.port = lib.mkOption {
        type = lib.types.int;
        default = 514;
      };
      logging.file = lib.mkOption {
        type = lib.types.str;
        default = "/var/log/nethsm.log";
      };
      exporter.port = lib.mkOption {
        type = lib.types.int;
        default = 8000;
      };
    };

    pkcs11 = {
      proxy.listenPort = lib.mkOption {
        type = lib.types.int;
        default = 2345;
      };
      proxy.listenAddr = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
      };
    };
  };

  config = {
    sops.secrets = {
      tls-pks-file.owner = "root";
      nethsm-metrics-credentials.owner = "root";
      nethsm-operator-password = {
        group = "wheel";
        mode = "0440";
      };
    };

    systemd.services.nethsm-exporter = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe nethsm-exporter} --hsm-host ${config.nethsm.host} --port ${toString config.nethsm.exporter.port}";
        EnvironmentFile = config.sops.secrets.nethsm-metrics-credentials.path;
      };
    };

    services.syslog-ng = {
      enable = true;
      extraConfig = ''
        source s_network_udp { network(ip("0.0.0.0") port(${toString config.nethsm.logging.port}) transport("udp")); };
        source s_network_tcp { network(ip("0.0.0.0") port(${toString config.nethsm.logging.port}) transport("tcp")); };

        destination d_nethsm { file("${config.nethsm.logging.file}" perm(0644)); };

        log { source(s_network_udp); destination(d_nethsm); };
        log { source(s_network_tcp); destination(d_nethsm); };
      '';
    };

    networking.firewall = {
      allowedUDPPorts = [ config.nethsm.logging.port ];
      allowedTCPPorts = [ config.nethsm.logging.port ];
    };

    users.groups.nethsm = { };

    systemd.tmpfiles.rules = [
      "f /var/log/libnethsm.log 0770 root nethsm - -"
    ];

    # https://docs.nitrokey.com/nethsm/pkcs11-setup#configuration-file-format
    sops.templates."p11nethsm.conf" = {
      content = # yaml
        ''
          # Trace, Debug, Info, Warn, Error
          log_level: Warn
          log_file: /var/log/libnethsm.log

          slots:
            - label: NetHSM
              description: Tampere Office NetHSM

              operator:
                username: ${nethsm-operator-username}
                password: ${config.sops.placeholder.nethsm-operator-password}

              instances:
                - url: https://${config.nethsm.host}/api/v1
                  max_idle_connections: 10

                  # This should be avoided if possible and certainly not used with a productive NetHSM.
                  danger_insecure_cert: true
                  # TODO: use fingerprint instead
                  # sha256_fingerprints:
                  #   - ""

              # Configure whether the certificates stored in the nethsm are stored in PEM or DER
              # The nethsm itself supports both, but some tooling may only support one of the encodings.
              # Valid values are PEM or DER. Defaults to PEM
              certificate_format: DER

              timeout_seconds: 10
              retries:
                count: 3
                delay_seconds: 1
        '';

      path = "/etc/nitrokey/p11nethsm.conf";
      group = "nethsm";
      mode = "0440";
    };

    environment.systemPackages =
      (with pkgs; [
        openssl
        screen
        minicom
        pynitrokey # nitropy
        opensc # pkcs11-tool
        gnutls # psktool
        yubihsm-shell
        p11-kit
      ])
      ++ (with inputs.ci-yubi.packages.${pkgs.stdenv.hostPlatform.system}; [
        cert-to-auth
      ])
      ++ [
        systemd-sbsign
        pkcs11-proxy
        nethsm-cmd
        get-secureboot-keys
      ];

    # PKCS#11 modules that p11-kit will load
    # https://p11-glue.github.io/p11-glue/p11-kit/manual/pkcs11-conf.html
    environment.etc = {
      # NetHSM module, used by the proxy
      "pkcs11/modules/nethsm.module".text = ''
        module: ${pkcs11Modules.nethsm}
        priority: 3
      '';
      # YubiHSM module, disabled in the proxy
      # Can be used as backup if NetHSM is not functional, by enabling it
      "pkcs11/modules/yubihsm.module".text = ''
        module: ${pkcs11Modules.yubihsm}
        priority: 2
        disable-in: pkcs11-daemon
      '';
    };

    environment.variables = {
      # can be used with pkcs11-tool --module
      P11MODULE = pkcs11Modules.p11-kit;

      # https://docs.yubico.com/hardware/yubihsm-2/hsm-2-user-guide/hsm2-sdk-tools-libraries.html#hsm2-pkcs11-configuration-sample-label
      YUBIHSM_PKCS11_CONF = toString (
        pkgs.writeText "yubihsm_pkcs11.conf" ''
          connector=http://127.0.0.1:12345
        ''
      );

      # https://github.com/latchset/pkcs11-provider/blob/main/HOWTO.md
      OPENSSL_CONF = toString (
        pkgs.writeText "openssl.cnf" # toml
          ''
            openssl_conf = openssl_init

            [openssl_init]
            providers = provider_sect

            [provider_sect]
            default = default_sect
            pkcs11 = pkcs11_sect

            # basic openssl functionality such as tls breaks when default provider is not present
            [default_sect]
            activate = 1

            [pkcs11_sect]
            activate = 1
            module = ${pkcs11-provider}/lib/ossl-modules/pkcs11.so
            pkcs11-module-path = ${pkcs11Modules.p11-kit}
            pkcs11-module-quirks = no-deinit
          ''
      );

      # Use this when providers aren't supported
      OPENSSL_CONF_LEGACY_ENGINE = toString (
        pkgs.writeText "openssl.cnf" # toml
          ''
            openssl_conf = openssl_init

            [openssl_init]
            engines = engine_section

            [engine_section]
            pkcs11 = pkcs11_section

            [pkcs11_section]
            engine_id = pkcs11
            dynamic_path = ${pkgs.libp11}/lib/engines/pkcs11.so
            MODULE_PATH = ${pkcs11Modules.p11-kit}
            init = 0
          ''
      );

      # Extra cert creation config can be loaded from ci-yubi repo
      OPENSSL_EXTRA_CONF = "${inputs.ci-yubi}/secboot/conf";
    };

    systemd.services.yubihsm-connector = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.yubihsm-connector} -d -t 5000";
      };
    };

    systemd.services.pkcs11-daemon = {
      wantedBy = [ "multi-user.target" ];

      environment = {
        PKCS11_DAEMON_SOCKET = "tls://${config.pkcs11.proxy.listenAddr}:${toString config.pkcs11.proxy.listenPort}";
        PKCS11_PROXY_TLS_PSK_FILE = config.sops.secrets.tls-pks-file.path;
      };

      serviceConfig = {
        ExecStart = "${lib.getExe pkcs11-proxy} ${pkcs11Modules.p11-kit}";
      };
    };
  };
}
