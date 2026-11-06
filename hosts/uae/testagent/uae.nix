# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  self,
  config,
  lib,
  ...
}:
let
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
  ];
in
{
  imports = [ ../../testagent/host-common.nix ];

  services.testagent.testCredentialFiles = lib.genAttrs robotSecrets (
    name: config.sops.secrets.${name}.path
  );

  sops.secrets = lib.genAttrs robotSecrets (_: {
    sopsFile = ./credentials.yaml;
    owner = "jenkins";
  });

  # The monitoring server cannot reach the UAE lab network.
  services.monitoring.metrics.push = true;

  environment.etc."jenkins/GhafInfraSignECP256.pem".source =
    "${self.outPath}/keys/GhafInfraSignECP256.pem";
}
