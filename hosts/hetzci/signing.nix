# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.hetzci.signing;

  inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) pkcs11-proxy systemd-sbsign;

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

  proxyEnv = {
    PKCS11_PROXY_MODULE = "${pkcs11-proxy}/lib/libpkcs11-proxy.so";
    PKCS11_PROXY_TLS_PSK_FILE = config.sops.secrets.tls-pks-file.path;
    PKCS11_PROXY_SOCKET = "tls://172.31.141.51:2345";
    PKCS11_TLS_IDENTITY = config.networking.hostName;
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
          pkcs11-module-path = "${pkcs11-proxy}/lib/libpkcs11-proxy.so"
          # fixes segfault in openssl commands
          pkcs11-module-quirks = no-deinit
        ''
    );
  };

  signingPackages =
    (with pkgs; [
      opensc # pkcs11-tool
      openssl
    ])
    ++ (with inputs.ci-yubi.packages.${pkgs.stdenv.hostPlatform.system}; [
      uefisign
      uefisigniso
      uefisign-simple
    ])
    ++ (with self.packages.${pkgs.stdenv.hostPlatform.system}; [
      verify-signature
    ])
    ++ [
      systemd-sbsign
    ];
in
{
  options.hetzci.signing = {
    proxy.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the pkcs11-proxy configuration";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.proxy.enable {
      sops.secrets = {
        tls-pks-file = {
          owner = "jenkins";
          group = "wheel";
          mode = "0440";
        };
      };

      environment.variables = proxyEnv;
      services.jenkins.environment = proxyEnv;
    })
    {
      environment.etc = {
        "jenkins/keys/secboot".source = "${self.outPath}/keys/secboot";
        "jenkins/keys/tempDBkey.pem".source = "${self.outPath}/keys/tempDBkey.pem";
        "jenkins/enroll-secureboot-keys.sh".source = "${self.outPath}/scripts/enroll-secureboot-keys.sh";
      };

      environment.systemPackages = signingPackages;
      services.jenkins.packages = signingPackages;
    }
  ];
}
