# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ self, ... }:
{
  services.testagent.credentialsFile = ./credentials.yaml;

  environment.etc."jenkins/GhafInfraSignECP256.pem".source =
    "${self.outPath}/keys/GhafInfraSignECP256.pem";
}
