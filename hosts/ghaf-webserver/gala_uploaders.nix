# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
let
  groupName = "gala";

  # add new uploaders here
  uploaders = [
    {
      desc = "Mikko Koivisto";
      name = "mikko_koivisto";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHx2xDbBcBFRCQ8vtA47UMT4zBasUWxK+1CYOQSrv2BL mikko_koivisto@Mikkos-MacBook-Pro.local"
      ];
    }
  ];
in
{
  users = {
    groups."${groupName}" = { };

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
          extraGroups = [ groupName ];
        }
      ) uploaders
    );
  };
}
