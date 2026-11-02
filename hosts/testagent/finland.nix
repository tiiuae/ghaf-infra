# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  pkgs,
  config,
  lib,
  inputs,
  self,
  ...
}:
let
  keySource = inputs.ghaf-infra-pki.packages.${pkgs.stdenv.hostPlatform.system}.yubi-slsa-pki;
  robotSecrets = [
    "dut-pass"
    "plug-login"
    "plug-pass"
    "switch-token"
    "switch-secret"
    "wifi-ssid"
    "wifi-password"
    "pi-login"
    "pi-pass"
    "fleetdm_enroll_secret"
    "fleetdm_api_token"
    "test-server-login"
    "test-server-pass"
  ];
in
{
  imports = [
    ./host-common.nix
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    nebula
    common
    openssh
    team-devenv
    team-testers
  ]);

  services.testagent.testCredentialFiles = lib.genAttrs robotSecrets (
    name: config.sops.secrets.${name}.path
  );

  sops.secrets = lib.genAttrs robotSecrets (_: {
    sopsFile = ./credentials.yaml;
    owner = "jenkins";
  });

  nebula.enable = true;

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
