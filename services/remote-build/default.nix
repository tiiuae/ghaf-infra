# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
_: {
  # Adds a "remote-build" ssh user, which can trigger nix builds.
  # TODO: once they all use a common binary cache, we can drop the trusted user
  # statement, so jenkins can't copy store paths, but builders can only
  # substitute.
  nix.settings.trusted-users = [ "remote-build" ];
  users.users.remote-build = {
    isNormalUser = true;
    name = "remote-build";
  };
}
