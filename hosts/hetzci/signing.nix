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

  proxyConfig = {
    PKCS11_PROXY_MODULE = "${selfPackages.pkcs11-proxy}/lib/libpkcs11-proxy.so";
    PKCS11_PROXY_TLS_PSK_FILE = config.sops.secrets.tls-pks-file.path;
    PKCS11_PROXY_SOCKET = "tls://nethsm-gateway.sumu.vedenemo.dev:2345";
  };
in
{
  sops.secrets = {
    tls-pks-file = {
      owner = "jenkins";
      group = "wheel";
    };
  };

  environment.systemPackages = with pkgs; [
    opensc # pkcs11-tool
    cosign
  ];

  environment.variables = proxyConfig;

  services.jenkins = {
    environment = proxyConfig;
    packages = with pkgs; [
      cosign
    ];
  };
}
