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
  stateDir = "/var/lib/softhsm";
  keyDir = stateDir + "/keys";
  tokenDir = stateDir + "/tokens";

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

  # nixpkgs provides 2.6.1, which is from 2020.
  # softhsm2 has not had a new release or tag in over 5 years.
  # Using the latest from git is better than using an outdated release.
  softhsm2 = pkgs.stdenv.mkDerivation {
    pname = "softhsm2";
    version = "develop";

    src = pkgs.fetchFromGitHub {
      owner = "softhsm";
      repo = "SoftHSMv2";
      # head of develop branch
      rev = "25b94d4752739fc5954e7eb3a404810db5d632fa";
      sha256 = "sha256-yjcS8Jm7XAEqa1DrE0FcbccvubcRl+UlUeNp56NUVi8=";
    };

    nativeBuildInputs = with pkgs; [
      autoreconfHook
      openssl
      sqlite
    ];

    # use openssl backend instead of botan
    # https://github.com/openssl/openssl/issues/22508#issuecomment-2646121200
    configureFlags = [
      "--with-crypto-backend=openssl"
      "--with-openssl=${lib.getDev pkgs.openssl}"
      "--with-objectstore-backend-db"
      "--sysconfdir=$out/etc"
      "--localstatedir=$out/var"
    ];

    postInstall = "rm -rf $out/var";
  };

  softhsmModule = "${softhsm2}/lib/softhsm/libsofthsm2.so";

  softhsmConf = pkgs.writeText "softhsm2.conf" ''
    directories.tokendir = ${tokenDir}
    objectstore.backend = file
    log.level = INFO
    slots.removable = false
    slots.mechanisms = ALL
    library.reset_on_fork = false
  '';

  inherit (self.packages.${pkgs.system}) pkcs11-proxy systemd-sbsign;
in
{
  sops.secrets = {
    tls-pks-file = {
      owner = "root";
      group = "softhsm";
      mode = "0440";
    };
  };

  environment.systemPackages =
    (with pkgs; [
      openssl
      pynitrokey # nitropy
      opensc # pkcs11-tool
      gnutls # psktool
    ])
    ++ [
      systemd-sbsign
      softhsm2
      pkcs11-proxy
    ];

  users.groups.softhsm = { };

  systemd.tmpfiles.rules = [
    "d ${tokenDir} 0770 root softhsm - -"
    "d ${keyDir} 0770 root softhsm - -"
  ];

  environment.variables = {
    KEYDIR = keyDir;
    SOFTHSM2_MODULE = softhsmModule;
    SOFTHSM2_CONF = toString softhsmConf; # toString will get the path to the file

    # Using a modern OpenSSL 3 provider for pkcs11 instead of legacy engine
    # https://github.com/latchset/pkcs11-provider/blob/main/HOWTO.md
    OPENSSL_CONF = toString (
      pkgs.writeText "openssl.cnf" # ini
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
          module = "${pkcs11-provider}/lib/ossl-modules/pkcs11.so"
          pkcs11-module-path = ${softhsmModule}
          # quirks for softhsm2 to avoid segfault
          # see https://github.com/latchset/pkcs11-provider/blob/663dea335c80bec7fd96d544ff875af08d6461a9/tests/softhsm-init.sh#L64
          # and https://github.com/openssl/openssl/issues/22508#issuecomment-1780033252
          pkcs11-module-quirks = no-deinit no-operation-state
        ''
    );

    # Extra cert creation config can be loaded from ci-yubi repo
    OPENSSL_EXTRA_CONF = "${inputs.ci-yubi}/secboot/conf";

    PKCS11_PROXY_SOCKET = "tcp://127.0.0.1:2345";
    PKCS11_PROXY_MODULE = "${pkcs11-proxy}/lib/libpkcs11-proxy.so";
  };

  systemd.services.pkcs11-daemon = {
    wantedBy = [ "multi-user.target" ];
    environment = {
      SOFTHSM2_CONF = toString softhsmConf;
      # listen on all interfaces using tls
      PKCS11_DAEMON_SOCKET = "tls://0.0.0.0:2345";
      PKCS11_PROXY_TLS_PSK_FILE = config.sops.secrets.tls-pks-file.path;
    };
    serviceConfig = {
      ExecStart = "${lib.getExe pkcs11-proxy} ${softhsmModule}";
    };
  };
}
