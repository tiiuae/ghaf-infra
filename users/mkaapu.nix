# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    mkaapu = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE6WDXGfrD+WfY2+eP+/c4NrEOeCGpEOE2TcTlwxWXho marko.kaapu@unikie.com"
      ];
      extraGroups = ["wheel" "networkmanager"];
    };
  };
}
