# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  flake.nixosModules = {
    service-binary-cache = import ./binary-cache;
    service-nginx = import ./nginx;
    service-monitoring = import ./monitoring;
    service-openssh = import ./openssh;
    service-remote-build = import ./remote-build;
    service-rclone-http = import ./rclone-http;
  };
}
