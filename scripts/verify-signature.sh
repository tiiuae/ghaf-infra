#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") MODE ARTIFACT SIGNATURE SIGNING_KEY

Verify the signature of image, provenance, or release attestation file with the
certificate identified by the PKCS#11 signing key URI recorded in the manifest.

Options:
  MODE: either 'provenance', 'release', or 'image'.
  ARTIFACT: the original file to verify.
  SIGNATURE: the signature file to verify against.
  SIGNING_KEY: PKCS#11 URI from the signature's signing_key manifest field.
EOF
  exit 1
}

if [[ $# -ne 4 ]]; then
  usage
fi

ARTIFACT=$2
SIGNATURE=$3
SIGNING_KEY=$4

verify-provenance() {
  openssl pkeyutl -verify -inkey "$CERT" -certin -sigfile "$SIGNATURE" -in "$ARTIFACT" -rawin
}

verify-release() {
  # Release policy attestations are signed with the provenance signing key for now.
  # Keep a separate mode so callers do not need to change if a dedicated release
  # signing key is introduced later.
  verify-provenance
}

verify-image() {
  openssl dgst \
    -verify <(openssl x509 -pubkey -noout -in "$CERT") \
    -signature "$SIGNATURE" \
    "$ARTIFACT"
}

choose-cert() {
  if [[ $SIGNING_KEY != pkcs11:* ]]; then
    echo "Invalid signing key URI: $SIGNING_KEY" >&2
    exit 1
  fi

  local parameters=";${SIGNING_KEY#pkcs11:};"
  if [[ $parameters =~ \;token=([^\;]+)\; ]]; then
    local token="${BASH_REMATCH[1]}"
  else
    echo "Signing key URI has no token: $SIGNING_KEY" >&2
    exit 1
  fi
  if [[ $parameters =~ \;object=([^\;]+)\; ]]; then
    local object="${BASH_REMATCH[1]}"
  else
    echo "Signing key URI has no object: $SIGNING_KEY" >&2
    exit 1
  fi
  if [[ ! $object =~ ^[[:alnum:]_.-]+$ ]]; then
    echo "Invalid signing key object: $object" >&2
    exit 1
  fi

  case "$token" in
  NetHSM) echo "$NETHSM_CERT_DIR/$object.pem" ;;
  YubiHSM) echo "$YUBIHSM_CERT_DIR/$object.pem" ;;
  *)
    echo "Unknown signing key token: $token" >&2
    exit 1
    ;;
  esac
}

CERT="$(choose-cert)"
if [[ ! -f $CERT ]]; then
  echo "Certificate for signing key not found: $CERT" >&2
  exit 1
fi
echo "Using certificate $CERT" >&2

if [[ $1 == "image" ]]; then
  verify-image
elif [[ $1 == "provenance" ]]; then
  verify-provenance
elif [[ $1 == "release" ]]; then
  verify-release
else
  usage
fi
