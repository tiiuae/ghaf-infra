# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    kiran = {
      description = "Kiran Bisht";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFez62rU8RbnXU59UOEbHj2STRdMGN0BgNCpmK3Lnndw kiran.bisht@tii.ae"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAEq7RIyMyN8hB19GGiKZqNJNLNm7YXbqTxB9aQs+sOt kiran.bisht@tii.ae"
      ];
      extraGroups = [ "wheel" ];
    };
  };
}
