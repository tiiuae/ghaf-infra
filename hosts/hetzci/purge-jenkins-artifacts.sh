#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -e # exit immediately if a command fails
set -E # exit immediately if a command fails (subshells)
set -u # treat unset variables as an error and exit

# Expected arguments and their defaults if not passed in environment variables
# Always keep at least this many build artifacts for each pipeline
PURGE_KEEP_BUILDS="${PURGE_KEEP_BUILDS:=3}"
# Skip purge if nix store disk usage is less than PURGE_DU_PCT percent
PURGE_DU_PCT="${PURGE_DU_PCT:=90}"

nix_store_du_pct=$( (df /nix/store --output=pcent || df /nix --output=pcent || df / --output=pcent) | tr -dc '0-9' )
echo "nix store disk usage: $nix_store_du_pct%"
if (( nix_store_du_pct < PURGE_DU_PCT )); then
  exit 0
fi

echo "Purge artifacts; removing all but the last $PURGE_KEEP_BUILDS builds on each pipeline"
# Outer loop finds the directories directly under /var/lib/jenkins/artifacts/,
# that is, the per-pipeline artifacts directories.
# Inner loop removes all but the latest PURGE_KEEP_BUILDS builds on each pipeline
while IFS= read -r path; do
  find "$path" -maxdepth 0 -exec ls -rt {} + | head -n -"$PURGE_KEEP_BUILDS" | while read -r x; do
    echo "Removing '$path/$x'"
    rm -fr "${path:?}/${x:?}"
  done
done < <(find /var/lib/jenkins/artifacts -maxdepth 1 -mindepth 1 -type d)
