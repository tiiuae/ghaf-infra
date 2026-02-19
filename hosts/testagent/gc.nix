# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  nix.gc = {
    automatic = true;
    dates = "daily";
    randomizedDelaySec = "45min";
    persistent = false;
    options = "--delete-older-than 14d";
  };
}
