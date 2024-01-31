# SPDX-FileCopyrightText: 2024 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{lib, ...}: let
  groupName = "developers";

  # add new developers here
  developers = [
    {
      name = "barna";
      keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQChDMYWXg51H1/3Y3fGb8Bn6Dj1jauzKKsPdtRjFHTWSCde4GmF1/uPUJ9qogLNBS2B0nDS+IxnNNIKWarZhkb1aHvWHBy1n1s4gULwCZcF36yaFfKKCIfro+YI1/1uOZuv/AtVLzAgFlgUb21xLF9m11yuobB6OqSd9Fxt8i2AdfwVuj1fxyRlI+l5v82g0d3KiN0Pw+FqtzIZ6sEcpw8Mqn469PIDARUmYxo7mRMug8QPmQPgv57YhbppLN6cHUbYlud/2UeESUFsXrCAMDLtghvkNlAlmriaqhlVoH3jTLJ8ljIbHeFrBidZZk1/e7Ucw8iLkesQ11YrAY0QqqyH6vRr/o0XHiCbnxJl7rH9AC8tguqgFR/K2T8qygJZfs1szaOQg/+O7tdqwU8+j2NDSuh+PjYGnMOIT11ErtAYB2DAd8xVYOOWCsLeHVoiC1jgkVjehkV4wmwmq3d7X5iyuK7n4zJTEIqDzbrfshUnpL9ERe7zlFaocqUVedn1DDU= barna.bakos@unikie.com"
      ];
    }
    {
      name = "bmg";
      keys = [
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIEJ9ewKwo5FLj6zE30KnTn8+nw7aKdei9SeTwaAeRdJDAAAABHNzaDo="
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIA/pwHnzGNM+ZU4lANGROTRe2ZHbes7cnZn72Oeun/MCAAAABHNzaDo="
      ];
    }
  ];
in {
  users = {
    groups."${groupName}" = {};

    users = builtins.listToAttrs (
      map (
        {
          name,
          keys,
        }:
          lib.nameValuePair name {
            inherit name;

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
