#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -e # exit immediately if a command fails
set -E # exit immediately if a command fails (subshells)
set -u # treat unset variables as an error and exit

# Expected arguments and their defaults if not passed in environment variables
# Trigger purge when disk usage is more than PURGE_DU_PCT percent
PURGE_DU_PCT="${PURGE_DU_PCT:=85}"
# On each invocation of this script, delete this percentage of builds per
# pipeline, always keeping at least the newest build.
PURGE_BUILD_PCT="${PURGE_BUILD_PCT:=20}"

purge() {
  # Cleanup /tmp: delete large files owned by jenkins modified at least 24 hours ago
  echo "Cleanup files from /tmp"
  find /tmp/ -mindepth 1 -type f -size +1G -user jenkins -mtime +1 -print -delete 2>/dev/null || true
  # Remove jenkins artifacts from /var/lib/jenkins/artifacts.
  # Outer loop finds the directories directly under /var/lib/jenkins/artifacts/,
  # that is, the per-pipeline artifacts directories. Inner loop removes the oldest
  # builds per pipeline rounding by ceil % (ensures some removal once deletable > 0),
  # always keeping at least the newest build per each pipeline.
  echo "Cleanup jenkins artifacts"
  while IFS= read -r path; do
    build_count=$(find "$path" -maxdepth 1 -mindepth 1 -type d -printf '.' 2>/dev/null | wc -c | tr -d ' ')
    if ((build_count <= 1)); then
      continue
    fi
    deletable=$((build_count - 1))
    remove_count=$(((deletable * PURGE_BUILD_PCT + 99) / 100))
    if ((remove_count < 1)); then
      continue
    fi
    if ((remove_count > deletable)); then
      remove_count=$deletable
    fi
    echo "Removing $remove_count build(s) from '$path'"
    deleted=0
    while IFS= read -r -d '' entry; do
      entry_path=${entry#* }
      echo "Removing '$entry_path'"
      rm -fr "$entry_path"
      deleted=$((deleted + 1))
      if ((deleted >= remove_count)); then
        break
      fi
    done < <(find "$path" -maxdepth 1 -mindepth 1 -type d -printf '%T@ %p\0' | sort -z -n)
  done < <(find /var/lib/jenkins/artifacts -maxdepth 1 -mindepth 1 -type d)
}

opt='--output=pcent'
du_jenkins_pct=$( (df /var/lib/jenkins/artifacts $opt || df / $opt) | tr -dc '0-9')
du_nix_store_pct=$( (df /nix/store $opt || df /nix $opt || df / $opt) | tr -dc '0-9')
echo "Disk usage on jenkins artifacts disk: $du_jenkins_pct%"
echo "Disk usage on nix store disk: $du_nix_store_pct%"
if ((du_jenkins_pct > PURGE_DU_PCT)) || ((du_nix_store_pct > PURGE_DU_PCT)); then
  purge
fi
if ((du_nix_store_pct > PURGE_DU_PCT)); then
  # Trigger nix gc if the cleanup was initiated due to nix store disk usage. Respect
  # the max-free config: collect garbage until at least max-free bytes have been
  # deleted, then stop.
  maxfree=$(nix config show | grep 'max-free =' | tr -dc '0-9')
  maxfree="${maxfree:=100G}" # default, if parsing nix config show failed
  echo "Trigger nix garbage collection (max-free=$maxfree)"
  nix-store --gc --max-freed "$maxfree"
fi
