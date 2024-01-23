# SPDX-FileCopyrightText: 2024 Technology Innovation Institute (TII)
# SPDX-License-Identifier: Apache-2.0
#
{...}: {
  imports = [
    # Import Ficolo x86 builder specific configuration
    ./builder.nix
  ];

  # build4 specific configuration

  networking.hostName = "build4";
}
