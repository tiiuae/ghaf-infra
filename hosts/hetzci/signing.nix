# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  config,
  ...
}:
let
  selfPackages = self.packages.${pkgs.system};

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

  proxyConfig = {
    PKCS11_PROXY_MODULE = "${selfPackages.pkcs11-proxy}/lib/libpkcs11-proxy.so";
    PKCS11_PROXY_TLS_PSK_FILE = config.sops.secrets.tls-pks-file.path;
    PKCS11_PROXY_SOCKET = "tls://nethsm-gateway.sumu.vedenemo.dev:2345";
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
          pkcs11-module-path = "${selfPackages.pkcs11-proxy}/lib/libpkcs11-proxy.so"
        ''
    );

  };
in
{
  sops.secrets = {
    tls-pks-file = {
      owner = "jenkins";
      group = "wheel";
      mode = "0440";
    };
  };

  environment.systemPackages =
    (with pkgs; [
      opensc # pkcs11-tool
      cosign
      openssl
    ])
    ++ [ selfPackages.systemd-sbsign ];

  environment.variables = proxyConfig;

  services.jenkins = {
    environment = proxyConfig;
    packages = with pkgs; [
      cosign
    ];
  };
}
