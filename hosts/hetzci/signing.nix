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
  yubi-uefi-pki = inputs.ghaf-infra-pki.packages.${pkgs.stdenv.hostPlatform.system}.yubi-uefi-pki;
  slsa-pki = inputs.ghaf-infra-pki.packages.${pkgs.stdenv.hostPlatform.system}.slsa-pki;
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
      certificates = {
        uefi = {
          db = "${yubi-uefi-pki}/share/ghaf-infra-pki/uefi/DB.pem";
          pk = "${yubi-uefi-pki}/share/ghaf-infra-pki/uefi/PK.pem";
          kek = "${yubi-uefi-pki}/share/ghaf-infra-pki/uefi/KEK.pem";
        };
        ota = "${slsa-pki}/share/ghaf-infra-pki/slsa/nethsm-tampere-mca/GhafInfraSignOta-${config.services.ghaf-jenkins.envType}.pem";
      };
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
