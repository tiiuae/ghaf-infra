# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
name: mountpoint:
let
  installerKey = "/run/${name}-install.key";
in
{
  type = "luks";
  inherit name;
  settings.keyFile = installerKey;
  preCreateHook = ''
    (umask 077; head -c 64 /dev/random > ${installerKey})
  '';
  postCreateHook = "rm -f ${installerKey}";
  initrdUnlock = false;
  extraFormatArgs = [
    "--type=luks2"
    "--pbkdf=pbkdf2"
    "--pbkdf-force-iterations=1000"
  ];
  content = {
    type = "btrfs";
    inherit mountpoint;
  };
}
