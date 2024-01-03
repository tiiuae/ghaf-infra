# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  flake.nixosModules = {
    service-binary-cache = import ./binary-cache;
    service-hydra = import ./hydra;
    service-nginx = import ./nginx;
    service-node-exporter = import ./node-exporter;
    service-openssh = import ./openssh;
    service-remote-build = import ./remote-build;
  };
}
