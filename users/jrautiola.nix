# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    jrautiola = {
      description = "Joonas Rautiola";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6EoeiMBiiwfGJfQYyuBKg8rDpswX0qh194DUQqUotL joonas@buutti"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGlFqSQFoSSuAS1IjmWBFXie329I5Aqf71QhVOnLTBG+ joonas@x1"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB3h/Aj66ndKFtqpQ8H53tE9KbbO0obThC0qbQQKFQRr joonas@zeus"
      ];
      extraGroups = [
        "wheel"
        "networkmanager"
        "softhsm"
      ];
    };
  };
}
