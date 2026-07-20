# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  pkgs,
  inputs,
  self,
  config,
  ...
}:
let
  keySource = inputs.ghaf-infra-pki.packages.${pkgs.stdenv.hostPlatform.system}.yubi-slsa-pki;
in
{
  imports = [
    self.nixosModules.service-nebula
    self.nixosModules.team-testers
  ];

  services.testagent.credentialsFile = ./credentials.yaml;

  sops.secrets =
    let
      credential = {
        sopsFile = ./credentials.yaml;
        owner = "jenkins";
      };
    in
    {
      fleetdm_enroll_secret = credential;
      fleetdm_api_token = credential;
      nebula-cert.owner = config.nebula.user;
      nebula-key.owner = config.nebula.user;
    };

  nebula = {
    enable = true;
    cert = config.sops.secrets.nebula-cert.path;
    key = config.sops.secrets.nebula-key.path;
  };

  services.nebula.networks."vedenemo".firewall.inbound = [
    {
      port = 8000;
      proto = "tcp";
      groups = [ "scraper" ];
    }
  ];

  environment.etc."jenkins/GhafInfraSignECP256.pem".source =
    "${keySource}/share/ghaf-infra-pki/slsa/GhafInfraSignECP256.pem";
}
