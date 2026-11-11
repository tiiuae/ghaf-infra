#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") MODE ARTIFACT SIGNATURE SIGNING_KEY

Verify the signature of image, provenance, or release attestation file with the
configured certificates named after the PKCS#11 key object in the manifest.

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

case "$1" in
image | provenance | release) ;;
*) usage ;;
esac

ARTIFACT=$2
SIGNATURE=$3
SIGNING_KEY=$4

if [[ $SIGNING_KEY != pkcs11:* ]]; then
  echo "Invalid signing key URI: $SIGNING_KEY" >&2
  exit 1
fi

parameters=";${SIGNING_KEY#pkcs11:};"
if [[ $parameters =~ \;token=([^\;]+)\; ]]; then
  token="${BASH_REMATCH[1]}"
else
  echo "Signing key URI has no token: $SIGNING_KEY" >&2
  exit 1
fi
if [[ $parameters =~ \;object=([^\;]+)\; ]]; then
  object="${BASH_REMATCH[1]}"
else
  echo "Signing key URI has no object: $SIGNING_KEY" >&2
  exit 1
fi
if [[ ! $object =~ ^[[:alnum:]_.-]+$ ]]; then
  echo "Invalid signing key object: $object" >&2
  exit 1
fi

directories=$(jq -er --arg token "$token" '
  .[$token] | if length > 0 then .[] else error("no certificate directories for token: " + $token) end
' "$SIGNATURE_CERTIFICATE_DIRECTORIES_FILE")

while IFS= read -r directory; do
  CERT="$directory/$object.pem"
  [[ -f $CERT ]] || continue

  case "$1" in
  image)
    if ! openssl dgst -sha256 \
      -verify <(openssl x509 -pubkey -noout -in "$CERT" 2>/dev/null) \
      -signature "$SIGNATURE" "$ARTIFACT" >/dev/null 2>&1; then
      continue
    fi
    ;;
  provenance | release)
    if ! openssl pkeyutl -verify -inkey "$CERT" -certin \
      -sigfile "$SIGNATURE" -in "$ARTIFACT" -rawin >/dev/null 2>&1; then
      continue
    fi
    ;;
  esac
  echo "Verified signature using certificate: $CERT"
  exit 0
done <<<"$directories"

echo "No trusted certificate verified the signature for: $SIGNING_KEY" >&2
exit 1
