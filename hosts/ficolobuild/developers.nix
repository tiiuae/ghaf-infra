# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{lib, ...}: let
  groupName = "developers";

  # add new developers here
  developers = [
    {
      desc = "Barna Bakos";
      name = "barna";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHrmxamlb4JNX+lrN88rfEEskCM0A5MhGSKaA4CZDM8y barna.bakos@unikie.com"
      ];
    }
    {
      desc = "Brian McGillion";
      name = "bmg";
      keys = [
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIEJ9ewKwo5FLj6zE30KnTn8+nw7aKdei9SeTwaAeRdJDAAAABHNzaDo="
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIA/pwHnzGNM+ZU4lANGROTRe2ZHbes7cnZn72Oeun/MCAAAABHNzaDo="
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILu6O3swRVWAjP7J8iYGT6st7NAa+o/XaemokmtKdpGa builder key"
      ];
    }
    {
      desc = "Samuli Leivo";
      name = "leivos";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHRGczoQ78cjHdjEgKTyZeLKu/flWlvf+HepdUezZCDr root@nixos"
      ];
    }
    {
      desc = "Milla Valio";
      name = "milval";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGll9sWYdGc2xi9oQ25TEcI1D3T4n8MMXoMT+lJdE/KC root@nixos"
      ];
    }
    {
      desc = "Humaid Alqasimi";
      name = "humaid";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUlaLlxVlm1KZtoG3R/nHl/KJzmKaIyckDVE2rDJYH+"
      ];
    }
  ];
in {
  users = {
    groups."${groupName}" = {};

    users = builtins.listToAttrs (
      map (
        {
          desc,
          name,
          keys,
        }:
          lib.nameValuePair name {
            inherit name;

            description = desc;
            openssh.authorizedKeys.keys = keys;

            isNormalUser = true;
            extraGroups = [groupName];
          }
      )
      developers
    );
  };
  nix.settings.trusted-users = ["@${groupName}"];
}
