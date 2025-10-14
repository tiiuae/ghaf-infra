#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -e

TMPDIR="$(mktemp -d)"
trap 'rm -rf -- "$TMPDIR"' EXIT

FLAKE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
cd "$TMPDIR"

sops decrypt "$FLAKE_ROOT"/services/nebula/ca.key.crypt >"ca.key"
sops decrypt "$FLAKE_ROOT"/services/nebula/ca.crt.crypt >"ca.crt"

nebula-cert sign \
	-out-crt host.crt \
	-out-key host.key \
	"$@"

echo "nebula-cert: |"
sed -e 's/^/    /' host.crt
echo "nebula-key: |"
sed -e 's/^/    /' host.key
