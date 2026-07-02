#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") MODE ARTIFACT SIGNATURE

Verify the signature of image, provenance, or release attestation file with the
currently valid certificates.

Options:
  MODE: either 'provenance', 'release', or 'image'.
  ARTIFACT: the original file to verify.
  SIGNATURE: the signature file to verify against.
EOF
  exit 1
}

if [[ $# -ne 3 ]]; then
  usage
fi

ARTIFACT=$2
SIGNATURE=$3

verify-provenance() {
  echo "Using certificate $PROV_CERT"
  openssl pkeyutl -verify -inkey "$PROV_CERT" -certin -sigfile "$SIGNATURE" -in "$ARTIFACT" -rawin
}

verify-release() {
  # Release policy attestations are signed with the provenance signing key for now.
  # Keep a separate mode so callers do not need to change if a dedicated release
  # signing key is introduced later.
  verify-provenance
}

verify-image() {
  echo "Using certificate $IMG_CERT"
  TMPDIR="$(mktemp -d)"
  openssl x509 -pubkey -noout -in "$IMG_CERT" >"$TMPDIR/pubkey.pub"
  openssl dgst -verify "$TMPDIR/pubkey.pub" -signature "$SIGNATURE" "$ARTIFACT"
}

if [[ $1 == "image" ]]; then
  if [[ -z $IMG_CERT ]]; then
    echo 'Certificate IMG_CERT is not defined in the running environment!'
    exit 1
  fi
  verify-image
elif [[ $1 == "provenance" ]]; then
  if [[ -z $PROV_CERT ]]; then
    echo 'Certificate PROV_CERT is not defined in the running environment!'
    exit 1
  fi
  verify-provenance
elif [[ $1 == "release" ]]; then
  if [[ -z $PROV_CERT ]]; then
    echo 'Certificate PROV_CERT is not defined in the running environment!'
    exit 1
  fi
  verify-release
else
  usage
fi
