# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  inputs,
  lib,
  ...
}:
let
  keySourceUefi = inputs.ghaf-infra-pki.packages.${pkgs.stdenv.hostPlatform.system}.yubi-uefi-pki;
in
{
  config = lib.mkIf config.services.ghaf-jenkins.signing.enable {
    sops.secrets = {
      tls-pks-file = {
        owner = "jenkins";
        group = "wheel";
        mode = "0440";
      };
      yubihsm-pin = {
        owner = "jenkins";
        group = "wheel";
        mode = "0440";
      };
    };

    services.ghaf-jenkins.signing = {
      pinFile = config.sops.secrets.yubihsm-pin.path;
      uefi.certificateFile = "${keySourceUefi}/share/ghaf-infra-pki/uefi/DB.pem";
      proxy = {
        enable = true;
        endpoints = [
          {
            name = "tampere";
            socket = "tls://nethsm-gateway.sumu.vedenemo.dev:2345";
          }
          {
            name = "uae";
            socket = "tls://uae-nethsm-gateway.sumu.vedenemo.dev:2345";
          }
        ];
        tlsPskFile = config.sops.secrets.tls-pks-file.path;
      };
      keys = {
        provenance = [
          "pkcs11:token=NetHSM;object=GhafInfraSignProv-${config.services.ghaf-jenkins.envType}"
          "pkcs11:token=YubiHSM;object=GhafInfraSignProv-${config.services.ghaf-jenkins.envType}"
        ];
        image = [
          "pkcs11:token=NetHSM;object=GhafInfraSignECP256-${config.services.ghaf-jenkins.envType}"
          "pkcs11:token=YubiHSM;object=GhafInfraSignECP256-${config.services.ghaf-jenkins.envType}"
        ];
        uefi = [
          # "pkcs11:token=NetHSM;object=uefi-ghaf-db"
          "pkcs11:token=YubiHSM;object=uefi-ghaf-db"
        ];
      };
    };
  };
}
