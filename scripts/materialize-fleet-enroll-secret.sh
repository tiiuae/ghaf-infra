#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

secret_file="${FLEET_ENROLL_SECRET_FILE:-/run/secrets/fleet_enroll_secret}"
secret_value="${FLEET_ENROLL_SECRET:-}"
dest="${FLEET_ENROLL_SECRET_DEST:-/persist/common/ghaf/fleet/enroll}"

mkdir -p "$(dirname "$dest")"

if [[ -n $secret_value ]]; then
  umask 077
  printf '%s' "$secret_value" >"$dest"
  echo "[+] Wrote Fleet enroll secret to $dest (from env)"
  exit 0
fi

if [[ -f $secret_file ]]; then
  umask 077
  install -m 600 "$secret_file" "$dest"
  echo "[+] Wrote Fleet enroll secret to $dest (from file)"
  exit 0
fi

echo "[+] Fleet enroll secret not provided; skipping"
