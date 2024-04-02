# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  flake.nixosModules = {
    service-binary-cache = import ./binary-cache;
    service-hydra = import ./hydra;
    service-nginx = import ./nginx;
    service-node-exporter = import ./node-exporter;
    service-openssh = import ./openssh;
    service-remote-build = import ./remote-build;
    service-rclone-http = import ./rclone-http;
  };
}
