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
Usage: $(basename "$0") [--regions REGIONS] [--tokens TOKENS] OBJECT

Finds the first pkcs11 signing node that works.

This script can either be sourced to populate the environment,
or executed normally to return json stdout for further processing.

Options:
  --regions REGIONS: comma-separated region list to try, defaults to ROUTER_PKCS11_REGIONS
  --tokens TOKENS: comma-separated token list to try, defaults to ROUTER_PKCS11_TOKENS
  OBJECT: The key that should be found on the node to consider it healthy

Environment:
  ROUTER_PKCS11_REGIONS: comma-separated region list to try. Default: tampere,uae
  ROUTER_PKCS11_TOKENS: comma-separated token list to try. Default: NetHSM,YubiHSM
  YUBIHSM_PIN: set to the pin of YubiHSM. When not specified, it's read from /run/secrets
EOF
}

ROUTER_PKCS11_REGIONS="${ROUTER_PKCS11_REGIONS:-tampere,uae}"
ROUTER_PKCS11_TOKENS="${ROUTER_PKCS11_TOKENS:-NetHSM,YubiHSM}"
OBJECT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --regions)
    if [[ $# -lt 2 ]]; then
      usage
      # shellcheck disable=SC2317
      return 1 2>/dev/null || exit 1
    fi
    ROUTER_PKCS11_REGIONS="$2"
    shift 2
    ;;
  --tokens)
    if [[ $# -lt 2 ]]; then
      usage
      # shellcheck disable=SC2317
      return 1 2>/dev/null || exit 1
    fi
    ROUTER_PKCS11_TOKENS="$2"
    shift 2
    ;;
  --)
    shift
    if [[ $# -ne 1 || -n $OBJECT ]]; then
      usage
      # shellcheck disable=SC2317
      return 1 2>/dev/null || exit 1
    fi
    OBJECT="$1"
    shift
    ;;
  -*)
    usage
    # shellcheck disable=SC2317
    return 1 2>/dev/null || exit 1
    ;;
  *)
    if [[ -n $OBJECT ]]; then
      usage
      # shellcheck disable=SC2317
      return 1 2>/dev/null || exit 1
    fi
    OBJECT="$1"
    shift
    ;;
  esac
done

if [[ -z $OBJECT ]]; then
  usage
  # shellcheck disable=SC2317
  return 1 2>/dev/null || exit 1
fi

YUBIHSM_PIN="${YUBIHSM_PIN:-$(cat /run/secrets/yubihsm-pin 2>/dev/null || true)}"

# the default timeout for unreachable pkcs11 proxy is minutes, we want to exit much earlier than that
SOCKET_TIMEOUT="${SOCKET_TIMEOUT:-30s}"

if [[ -z $ROUTER_PKCS11_REGIONS || $ROUTER_PKCS11_REGIONS == ,* || $ROUTER_PKCS11_REGIONS == *, || $ROUTER_PKCS11_REGIONS == *,,* ]]; then
  echo "Error: ROUTER_PKCS11_REGIONS/--regions contains an empty region" 1>&2
  # shellcheck disable=SC2317
  return 1 2>/dev/null || exit 1
fi

if [[ -z $ROUTER_PKCS11_TOKENS || $ROUTER_PKCS11_TOKENS == ,* || $ROUTER_PKCS11_TOKENS == *, || $ROUTER_PKCS11_TOKENS == *,,* ]]; then
  echo "Error: ROUTER_PKCS11_TOKENS/--tokens contains an empty token" 1>&2
  # shellcheck disable=SC2317
  return 1 2>/dev/null || exit 1
fi

if [[ -z $YUBIHSM_PIN ]]; then
  echo "Warning: YUBIHSM_PIN is empty. Connection to YubiHSMs will most likely fail." 1>&2
fi

IFS=, read -r -a PKCS11_TOKENS <<<"$ROUTER_PKCS11_TOKENS"
IFS=, read -r -a PKCS11_REGIONS <<<"$ROUTER_PKCS11_REGIONS"

# sockets are tried in this order
PKCS11_SOCKETS=()
for region in "${PKCS11_REGIONS[@]}"; do
  case "$region" in
  tampere)
    PKCS11_SOCKETS+=("tampere=tls://nethsm-gateway.sumu.vedenemo.dev:2345")
    ;;
  uae)
    PKCS11_SOCKETS+=("uae=tls://uae-nethsm-gateway.sumu.vedenemo.dev:2345")
    ;;
  *)
    echo "Error: unsupported region '$region'" 1>&2
    # shellcheck disable=SC2317
    return 1 2>/dev/null || exit 1
    ;;
  esac
done

for token in "${PKCS11_TOKENS[@]}"; do
  for socket_config in "${PKCS11_SOCKETS[@]}"; do
    region="${socket_config%%=*}"
    socket="${socket_config#*=}"
    uri="pkcs11:token=$token;object=$OBJECT"

    echo "[>] Checking $token on $socket ($region)" 1>&2
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
        export PKCS11_REGION="$region"
        echo "Exported into environment:"
        echo "> PKCS11_PROXY_SOCKET=$socket"
        echo "> PKCS11_TOKEN=$token"
        echo "> PKCS11_URI=$uri"
        echo "> PKCS11_REGION=$region"
        return 0
      else
        jq -n \
          --arg socket "$socket" \
          --arg token "$token" \
          --arg uri "$uri" \
          --arg region "$region" \
          '{
            socket: $socket,
            token: $token,
            uri: $uri,
            region: $region
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
