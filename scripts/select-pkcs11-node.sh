#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Detect whether this file is sourced or executed
_sourced=0
if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
  _sourced=1
fi

# Save caller's shell option state before changing it
_old_shell_opts="$(set +o)"
_old_shopt_opts="$(shopt -p)"

cleanup_shell_state() {
  local rc=$?
  eval "$_old_shell_opts"
  eval "$_old_shopt_opts"
  trap - EXIT RETURN

  if [[ $_sourced -eq 1 ]]; then
    return "$rc"
  else
    exit "$rc"
  fi
}

if [[ $_sourced -eq 1 ]]; then
  trap cleanup_shell_state RETURN
else
  trap cleanup_shell_state EXIT
fi

set -e

usage() {
  cat <<EOF
Usage: $(basename "$0") OBJECT

Finds the first pkcs11 signing node that works.

This script can either be sourced to populate the environment,
or executed normally to return json stdout for further processing.

Options:
  OBJECT: The key that should be found on the node to consider it healthy

Environment:
  YUBIHSM_PIN: set to the pin of YubiHSM. When not specified, it's read from /run/secrets
EOF
}

if [[ $# -ne 1 ]]; then
  usage
  # shellcheck disable=SC2317
  return 1 2>/dev/null || exit 1
fi

OBJECT="$1"
YUBIHSM_PIN="${YUBIHSM_PIN:-$(cat /run/secrets/yubihsm-pin 2>/dev/null || true)}"

# the default timeout for unreachable pkcs11 proxy is minutes, we want to exit much earlier than that
SOCKET_TIMEOUT="${SOCKET_TIMEOUT:-30s}"

if [[ -z $YUBIHSM_PIN ]]; then
  echo "Warning: YUBIHSM_PIN is empty. Connection to YubiHSMs will most likely fail." 1>&2
fi

# tokens are tried in this order
PKCS11_TOKENS=(
  "NetHSM"
  "YubiHSM"
)

# sockets are tried in this order
PKCS11_SOCKETS=(
  "tls://nethsm-gateway.sumu.vedenemo.dev:2345"
  "tls://uae-nethsm-gateway.sumu.vedenemo.dev:2345"
)

for token in "${PKCS11_TOKENS[@]}"; do
  for socket in "${PKCS11_SOCKETS[@]}"; do
    uri="pkcs11:token=$token;object=$OBJECT"

    echo "[>] Checking $token on $socket" 1>&2
    if GNUTLS_PIN="$YUBIHSM_PIN" \
      PKCS11_PROXY_SOCKET="$socket" \
      timeout "$SOCKET_TIMEOUT" \
      p11tool \
      --provider "$PKCS11_PROXY_MODULE" \
      --login \
      --list-all \
      "$uri" >/dev/null; then

      echo "Success!" 1>&2

      if [[ $_sourced -eq 1 ]]; then
        export PKCS11_PROXY_SOCKET="$socket"
        export PKCS11_TOKEN="$token"
        export PKCS11_URI="$uri"
        echo "Exported into environment:"
        echo "> PKCS11_PROXY_SOCKET=$socket"
        echo "> PKCS11_TOKEN=$token"
        echo "> PKCS11_URI=$uri"
        return 0
      else
        jq -n \
          --arg socket "$socket" \
          --arg token "$token" \
          --arg uri "$uri" \
          '{
            socket: $socket,
            token: $token,
            uri: $uri
          }'
        exit 0
      fi
    else
      rc=$?
      echo "Error! Exit code $rc" 1>&2
    fi
  done
done

# shellcheck disable=SC2317
return 1 2>/dev/null || exit 1
