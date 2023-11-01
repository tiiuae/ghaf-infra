# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    jrautiola = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6EoeiMBiiwfGJfQYyuBKg8rDpswX0qh194DUQqUotL joonas@buutti"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPjn9ZyVUkSuhcfpAtjrEQn2g1MhQdKc3vLLRqCz0tWk joonas@unikie"
      ];
      extraGroups = ["wheel" "networkmanager"];
    };
  };
}
