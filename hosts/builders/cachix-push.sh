#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-FileCopyrightText: 2018 GitHub, Inc. and contributors
# SPDX-License-Identifier: Apache-2.0

set -e # exit immediately if a command fails
set -E # exit immediately if a command fails (subshells)
set -u # treat unset variables as an error and exit

# Temporary workdir for the script
TMPDIR="$(mktemp -d --suffix .cachix-push)"

# Expected arguments and their defaults if not passed in environment variables
CACHIX_AUTH_TOKEN_FILE="${CACHIX_AUTH_TOKEN_FILE:=/dev/null}"
CACHIX_CACHE_NAME="${CACHIX_CACHE_NAME:=ghaf-dev}"

# Lists all nix store paths potentially pushed to cachix
list_nix_store_paths () {
    out=$1
    echo -n "" >"$out"
    # Following is (mostly) copied from:
    # https://github.com/cachix/cachix-action/blob/ee79d/dist/list-nix-store.sh
    for file in /nix/store/*; do
        case "$file" in
        *.drv)
            # Avoid .drv as they are not generally useful
            continue
            ;;
        *.drv.chroot)
            # Avoid .drv.chroot as they are not generally useful
            continue
            ;;
        *.check)
            # Skip .check file produced by --keep-failed
            continue
            ;;
        *.lock)
            # Skip .lock files
            continue
            ;;
        *.links)
            # Skip .links file populated by nix-store --optimize
            continue
            ;;
        *)
            echo "$file" >>"$out"
            ;;
        esac
    done
}

# Remove TMPDIR on exit
on_exit () {
    echo "[+] Stop (TMPDIR:$TMPDIR)"
    rm -fr "$TMPDIR"
}
trap on_exit EXIT

echo "[+] Start (TMPDIR=$TMPDIR)"

# Set cachix authentication token
cachix authtoken --stdin <"$CACHIX_AUTH_TOKEN_FILE"

# Snapshot current nix store paths as first reference
list_nix_store_paths "$TMPDIR/ref"
echo "[+] Initialized reference"

# Poll new store paths every 30 seconds
while sleep 30; do
    echo -n "" >"$TMPDIR/push"
    # Snapshot nix store paths for the current poll iteration
    list_nix_store_paths "$TMPDIR/snapshot"
    # Diff the ref and current snapshot to find new store paths since the last
    # diff. Use line group formats to output only new and changed lines.
    # For detailed description, see diff option --GTYPE-group-formats manual:
    diff \
        --unchanged-group-format='' --changed-group-format='%>' \
        --old-group-format='' --new-group-format='%>' \
        "$TMPDIR/ref" "$TMPDIR/snapshot" >"$TMPDIR/new" || true
    # Filter paths that match the following regexp
    filter='(nixos\.img$|\.iso$|\.raw\.zst|\.img\.zst|\-disko-images)'
    while read -r storepath; do
        # Also skip if the store path is a (symlink to) directory and any
        # directory contents matches the filter
        if find -L "$storepath" 2>/dev/null | grep -qP "$filter"; then
            continue
        fi
        # This store path will be pushed
        echo "$storepath" >>"$TMPDIR/push"
    done < <(grep -vP "$filter" "$TMPDIR/new")
    # Skip if all new store paths were filtered out
    if [ ! -s "$TMPDIR/push" ]; then
        continue;
    fi
    # Cachix push new store paths
    if ! cachix push -j4 -l16 "$CACHIX_CACHE_NAME" <"$TMPDIR/push"; then
        continue
    fi
    # Cachix push was successful: update the reference for next iteration
    cp -f "$TMPDIR/snapshot" "$TMPDIR/ref"
done
