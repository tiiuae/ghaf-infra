# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    lasse = {
      description = "Lasse Mattila";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIbcxJPaydRuDwR7c896FWyC4f5sL38qnyWs52XoHuDn lasse-mattila@lasse-mattila-ThinkPad-P1-Gen-6"
      ];
      extraGroups = [ "wheel" ];
    };
  };
}
