#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: MIT

#
# Builds a derivation at the given attribute path.
set -ueo pipefail

# Load input variables from Terraform. jq's @sh format takes care of
# escaping.
eval "$(jq -r '@sh "ATTRPATH=\(.attrpath) && ENTRYPOINT=\(.entrypoint)"')"

# Evaluate and build the derivation.
[[ -z "$ENTRYPOINT" ]] && ENTRYPOINT=$(git rev-parse --show-toplevel)
OUTPATH=$(nix-build --no-out-link -A "${ATTRPATH}" "${ENTRYPOINT}")

# Return the output path back to Terraform.
jq -n --arg outPath "$OUTPATH" '{"outPath":$outPath}'
