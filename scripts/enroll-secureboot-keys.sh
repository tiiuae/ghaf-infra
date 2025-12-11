#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

if ! command -v "efi-updatevar" &>/dev/null; then
  echo "command 'efi-updatevar' is not installed (Hint: nix-shell -p efitools)"
  exit 1
fi

check_file() {
  if [[ ! -f $1 ]]; then
    echo "File '$1 not found in current working directory'"
    exit 1
  fi
}

check_file db.crt
check_file KEK.crt
check_file PK.auth

if command -v "bootctl" &>/dev/null; then
  sudo bootctl | head -n 8
fi

set -x
sudo chattr -i /sys/firmware/efi/efivars/db-*
sudo chattr -i /sys/firmware/efi/efivars/KEK-*
sudo efi-updatevar -c db.crt db
sudo efi-updatevar -c KEK.crt KEK
sudo efi-updatevar -f PK.auth PK
