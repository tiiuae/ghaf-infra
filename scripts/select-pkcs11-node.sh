#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

if [[ $# -ne 1 || $1 == -* ]]; then
  echo "Usage: select-pkcs11-node PURPOSE" >&2
  echo "Try JENKINS_SIGNING_KEYS_FILE URIs in order across JENKINS_PKCS11_ENDPOINTS_FILE endpoints." >&2
  echo "SOCKET_TIMEOUT: timeout per probe (default: 75s)." >&2
  exit 1
fi

keys=$(jq -er --arg purpose "$1" '
  .[$purpose] | if length > 0 then .[] else error("no keys for signing purpose") end
' "$JENKINS_SIGNING_KEYS_FILE")
if [[ -n ${JENKINS_PKCS11_ENDPOINTS_FILE:-} ]]; then
  endpoints=$(jq -er '
    if length > 0 then .[] | [.name, .socket] | @tsv
    else error("no proxy endpoints") end
  ' "$JENKINS_PKCS11_ENDPOINTS_FILE")
else
  endpoints=$'local\t'
fi

if [[ -n ${YUBIHSM_PIN:-} ]]; then
  signing_pin=$YUBIHSM_PIN
elif [[ -n ${JENKINS_SIGNING_PIN_FILE:-} ]]; then
  signing_pin=$(<"$JENKINS_SIGNING_PIN_FILE")
else
  signing_pin=
fi
# Allow time for Nebula tunnels to recover while bounding how long an
# unreachable proxy delays selection.
SOCKET_TIMEOUT="${SOCKET_TIMEOUT:-75s}"

while IFS= read -r uri; do
  while IFS=$'\t' read -r region socket; do
    echo "[>] Checking $uri on $socket ($region)" >&2
    if GNUTLS_PIN="$signing_pin" \
      PKCS11_PROXY_SOCKET="$socket" \
      timeout "$SOCKET_TIMEOUT" \
      p11tool \
      --provider "$JENKINS_PKCS11_MODULE" \
      --login \
      --list-all \
      "$uri" >/dev/null; then
      jq -n \
        --arg socket "$socket" \
        --arg uri "$uri" \
        --arg region "$region" \
        '{socket: $socket, uri: $uri, region: $region}'
      exit 0
    fi
  done <<<"$endpoints"
done <<<"$keys"

echo "No available signing key for '$1'" >&2
exit 1
