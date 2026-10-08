#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

OCI_REGISTRY=${OCI_REGISTRY:-"registry.vedenemo.dev"}
OCI_USERNAME=${OCI_USERNAME:-"jenkins"}

if [[ -z ${OCI_PASSWORD:-} ]]; then
  echo "OCI_PASSWORD is empty, cannot sign without credentials!"
  exit 1
fi

if [[ -z ${COSIGN_PKCS11_MODULE_PATH:-} ]]; then
  COSIGN_PKCS11_MODULE_PATH="${PKCS11_PROXY_MODULE:-}"
fi
export COSIGN_PKCS11_MODULE_PATH

COSIGN_PKCS11_PIN="${YUBIHSM_PIN:-$(cat /run/secrets/yubihsm-pin 2>/dev/null || true)}"
export COSIGN_PKCS11_PIN

DOCKER_CONFIG="$(mktemp -d)"
export DOCKER_CONFIG

trap 'rm -rf "$DOCKER_CONFIG"' EXIT

printf '%s' "$OCI_PASSWORD" | cosign login "$OCI_REGISTRY" \
  --username "$OCI_USERNAME" \
  --password-stdin

cosign sign --yes "$@"
