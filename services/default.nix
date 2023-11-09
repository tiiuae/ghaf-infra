# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  flake.nixosModules = {
    service-binary-cache = import ./binary-cache;
    service-hydra = import ./hydra;
    service-nginx = import ./nginx;
    service-openssh = import ./openssh;
  };
}
