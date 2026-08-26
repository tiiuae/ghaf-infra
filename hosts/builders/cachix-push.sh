#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-FileCopyrightText: 2018 GitHub, Inc. and contributors
# SPDX-License-Identifier: Apache-2.0

set -e          # exit immediately if a command fails
set -E          # inherit ERR traps in subshells and functions
set -o pipefail # fail pipelines when any command fails
set -u          # treat unset variables as an error and exit

# Temporary workdir for the script
TMPDIR="$(mktemp -d --suffix .cachix-push)"

# Expected arguments and their defaults if not passed in environment variables
CACHIX_AUTH_TOKEN_FILE="${CACHIX_AUTH_TOKEN_FILE:=/dev/null}"
CACHIX_CACHE_NAME="${CACHIX_CACHE_NAME:=ghaf-dev}"
CACHIX_STATE_DIR="${CACHIX_STATE_DIR:=/var/lib/cachix-push}"
# Stop retrying once the persisted queue exceeds 100 MiB. With typical
# /nix/store paths at roughly 70 bytes per line including the newline, this is
# about 1.5 million queued store paths.
RETRY_FILE_MAX_BYTES="${RETRY_FILE_MAX_BYTES:=$((100 * 1024 * 1024))}"
# Persistent state files survive service restarts so we do not lose the
# baseline snapshot or the retry queue.
REF_FILE="$CACHIX_STATE_DIR/ref"
RETRY_FILE="$CACHIX_STATE_DIR/retry"
CURRENT_CACHIX_TOKEN_DIGEST=""

# Lists all nix store paths potentially pushed to cachix
list_nix_store_paths() {
  local out=$1
  local tmp

  tmp="$(mktemp --tmpdir="$(dirname "$out")" ".$(basename "$out").XXXXXX")"
  # https://github.com/cachix/cachix-action/blob/ee79d/dist/list-nix-store.sh
  # Builders and nix-daemon auto-GC can remove store entries while this snapshot
  # runs. find stats entries before applying the exclusions below, so even
  # ignored names such as *.drv.chroot can otherwise fail the whole poll.
  find /nix/store -ignore_readdir_race -mindepth 1 -maxdepth 1 \
    ! -name '*.drv' \
    ! -name '*.drv.chroot' \
    ! -name '*.check' \
    ! -name '*.lock' \
    ! -name '*.links' \
    ! -name '.tmp-link-*' \
    -print | LC_ALL=C sort >"$tmp"
  mv -f "$tmp" "$out"
}

# Store paths matching these image artifact names are unsafe to upload directly.
# Before pushing a batch, we also skip all current referrers of these paths
# because cachix push uploads every missing reference of an unfiltered root.
# The regex derivation below supports only literal characters, '*', and '.'.
IMAGE_FILTER_GLOBS=(
  '*-disko-images*'
  'nixos-image-sd-card-*.img*'
  'nixos-disk-image'
  '*.raw.zst'
  '*.img.zst*'
  'microvm-store-disk.*'
  'ghaf.iso'
  'nixos.img'
)

IMAGE_FILTER_REGEX=""
for image_filter_glob in "${IMAGE_FILTER_GLOBS[@]}"; do
  image_filter_regex_part="${image_filter_glob//./\\.}"
  image_filter_regex_part="${image_filter_regex_part//\*/.*}"

  if [ -n "$IMAGE_FILTER_REGEX" ]; then
    IMAGE_FILTER_REGEX+="|"
  fi
  IMAGE_FILTER_REGEX+="$image_filter_regex_part"
done
IMAGE_FILTER_REGEX="^/nix/store/[0-9a-z]{32}-(${IMAGE_FILTER_REGEX})$"

# Additional direct filters for files found near the top of store path
# directories. These are intentionally not closure-wide; applying them through
# NixOS system closures would skip too many ordinary paths.
FILTER_GLOBS=(
  "${IMAGE_FILTER_GLOBS[@]}"
  'set-environment'
  'etc-pam-environment'
)

FILTER_MATCH=""

# Set to 1 by the poll helpers when they cannot finish the current iteration.
# They report through this global and always return 0 so their callers can
# invoke them bare. Wrapping a function call in `if`, `!` or `||` disables
# errexit for the duration of that call, including inside everything the
# function itself calls, so an unguarded failure would be silently ignored
# instead of aborting the service and letting systemd restart it clean.
SKIP_POLL=0

# Return success when NAME matches any of the provided shell globs.
matches_any_glob() {
  local name=$1
  shift

  local pattern
  for pattern in "$@"; do
    # shellcheck disable=SC2254
    case "$name" in
    $pattern)
      return 0
      ;;
    esac
  done

  return 1
}

# Find the first path inside STOREPATH whose basename matches any filter glob.
# The search is depth bounded because the artifacts we filter sit at or near the
# top of their output directory, as in iso/ghaf.iso or sd-image/*.img.zst. An
# unbounded search matches unrelated payload deeper in ordinary packages:
# linux-firmware ships lib/firmware/**/*.img.zst, which made the whole package,
# and nothing else in its closure, silently unpushable. Depth 3 leaves headroom
# for grouped image layouts such as images/<arch>/main.raw.zst while staying
# well clear of that firmware payload, which sits five levels down.
find_first_matching_path() {
  local storepath=$1
  shift

  local find_args=("$storepath" -maxdepth 3 "(")
  local first=1
  local pattern
  for pattern in "$@"; do
    if [ "$first" -eq 0 ]; then
      find_args+=(-o)
    fi
    find_args+=(-name "$pattern")
    first=0
  done
  find_args+=(")" -print -quit)

  # Do not follow symlinks here. Some substituted source trees contain test
  # fixtures with filesystem loops, and `find -L` can hang walking them
  # before concluding there is nothing to filter.
  find "${find_args[@]}" 2>/dev/null || true
}

# Return success for store paths that should never be uploaded. Match both the
# top-level store path names we actually publish via Jenkins artifacts and the
# image files contained inside those store paths.
should_filter_store_path() {
  local storepath=$1
  local name
  local matched

  FILTER_MATCH=""
  name="${storepath##*/}"
  name="${name#*-}"

  if matches_any_glob "$name" "${FILTER_GLOBS[@]}"; then
    FILTER_MATCH="$storepath"
    return 0
  fi

  if [ -d "$storepath" ]; then
    matched="$(
      find_first_matching_path \
        "$storepath" \
        "${FILTER_GLOBS[@]}"
    )"
    if [ -n "$matched" ]; then
      FILTER_MATCH="$matched"
      return 0
    fi
  fi

  return 1
}

# Build the set of current roots that would upload a filtered image as a closure
# member. This deliberately skips useful roots too, such as ghaf-host toplevels,
# because cachix has no non-recursive push mode.
build_closure_filter_matches() {
  local snapshot=$1
  local matches=$2
  local image_paths="$TMPDIR/image-filter-paths"
  local referrers="$TMPDIR/image-referrers"
  local query_log="$TMPDIR/nix-store-query.err"
  local message
  local grep_status=0
  local query_status=0

  : >"$matches" || {
    SKIP_POLL=1
    return 0
  }
  : >"$image_paths" || {
    SKIP_POLL=1
    return 0
  }

  LC_ALL=C grep -E "$IMAGE_FILTER_REGEX" "$snapshot" >"$image_paths" 2>"$query_log" || grep_status=$?
  if [ "$grep_status" -eq 1 ]; then
    return 0
  fi
  if [ "$grep_status" -ne 0 ]; then
    message="$(head -n 1 "$query_log" || true)"
    if [ -z "$message" ]; then
      message="grep exited with status $grep_status"
    fi
    echo "[!] Failed to scan image filter paths from snapshot: $message" >&2
    SKIP_POLL=1
    return 0
  fi

  [ -s "$image_paths" ] || return 0
  LC_ALL=C sort -u "$image_paths" -o "$image_paths" || {
    SKIP_POLL=1
    return 0
  }

  # Query in chunks rather than passing every image path as a single argv.
  # Images accumulate between store garbage collections, and once the argument
  # list exceeds ARG_MAX the exec fails on every subsequent poll, which would
  # stop the service from ever advancing REF_FILE again. Store paths cannot
  # contain newlines, so -d skips xargs quote and backslash processing.
  xargs -r -a "$image_paths" -d '\n' -n 256 \
    nix-store -q --referrers-closure >"$referrers" 2>"$query_log" </dev/null ||
    query_status=$?
  if [ "$query_status" -ne 0 ]; then
    message="$(head -n 1 "$query_log" || true)"
    if [ -z "$message" ]; then
      # xargs reports 123 when a chunk failed and 125..127 when it could not run
      # nix-store at all. A signalled or OOM-killed child writes no stderr.
      message="referrer query exited with status $query_status"
    fi
    echo "[!] Failed to query image referrers: $message" >&2
    SKIP_POLL=1
    return 0
  fi

  LC_ALL=C sort -u "$referrers" -o "$matches" || {
    SKIP_POLL=1
    return 0
  }

  return 0
}

# Combine the persisted retry queue with newly discovered store paths while
# preserving retry-first order and removing duplicates.
merge_candidates() {
  local retry_file=$1
  local new_file=$2
  local candidates=$3

  : >"$candidates"
  # Bash associative arrays require bash 4+, which is fine on NixOS.
  # Keep retry entries first so previously failed pushes are retried before
  # newly discovered store paths.
  declare -A seen=()

  local storepath
  while read -r storepath; do
    [ -n "$storepath" ] || continue

    if [ -n "${seen["$storepath"]+x}" ]; then
      continue
    fi

    seen["$storepath"]=1
    echo "$storepath" >>"$candidates"
  done < <(cat "$retry_file" "$new_file")
}

# Walk the combined candidate list once, filtering unsupported paths and
# re-queueing only the paths whose cachix upload attempt failed.
process_candidates() {
  local candidates=$1
  local retry_next=$2
  local snapshot=$3
  local storepath
  local closure_filter_file="$TMPDIR/closure-filter-matches"
  local closure_filter_fd
  local candidates_fd
  declare -A closure_filter_matches=()

  # Keep stderr redirection before the target redirection so Bash's own
  # open/truncate error is suppressed and the journal gets one structured line.
  if ! : 2>/dev/null >"$retry_next"; then
    echo "[!] Failed to initialize retry queue: $retry_next" >&2
    SKIP_POLL=1
    return 0
  fi

  if ! { exec {candidates_fd}<"$candidates"; } 2>/dev/null; then
    echo "[!] Failed to read candidate store paths: $candidates" >&2
    SKIP_POLL=1
    return 0
  fi

  if [ ! -s "$candidates" ]; then
    exec {candidates_fd}<&-
    return 0
  fi

  build_closure_filter_matches "$snapshot" "$closure_filter_file"
  if [ "$SKIP_POLL" -ne 0 ]; then
    exec {candidates_fd}<&-
    echo "[!] Failed to inspect image referrers; skipping poll without advancing reference" >&2
    return 0
  fi

  if ! { exec {closure_filter_fd}<"$closure_filter_file"; } 2>/dev/null; then
    exec {candidates_fd}<&-
    echo "[!] Failed to read closure filter matches: $closure_filter_file" >&2
    SKIP_POLL=1
    return 0
  fi

  while read -r -u "$closure_filter_fd" storepath; do
    [ -n "$storepath" ] || continue
    if [ -z "${closure_filter_matches["$storepath"]+x}" ]; then
      closure_filter_matches["$storepath"]=1
    fi
  done
  exec {closure_filter_fd}<&-

  while read -r -u "$candidates_fd" storepath; do
    [ -n "$storepath" ] || continue

    if [ ! -e "$storepath" ]; then
      echo "[!] Skip vanished store path: $storepath" >&2
      continue
    fi

    if should_filter_store_path "$storepath"; then
      if [ "$FILTER_MATCH" != "$storepath" ]; then
        echo "[+] Skip filtered store path: $storepath (matched: $FILTER_MATCH)"
      else
        echo "[+] Skip filtered store path: $storepath"
      fi
      continue
    fi

    if [ -n "${closure_filter_matches["$storepath"]+x}" ]; then
      echo "[+] Skip filtered store path: $storepath (matched: filtered image closure)"
      continue
    fi

    local push_log="$TMPDIR/cachix-push.log"
    if ! cachix push -j4 -l16 "$CACHIX_CACHE_NAME" "$storepath" >"$push_log" 2>&1 </dev/null; then
      cat "$push_log" >&2
      echo "[!] Failed to push store path, will retry: $storepath" >&2
      # Keep stderr redirection before the append for the same reason as the
      # retry queue initialization above.
      if ! echo "$storepath" 2>/dev/null >>"$retry_next"; then
        exec {candidates_fd}<&-
        echo "[!] Failed to update retry queue: $retry_next" >&2
        SKIP_POLL=1
        return 0
      fi
      continue
    fi

    # Suppress the noisy per-path no-op message. Actual uploads still emit the
    # detailed cachix output so successful pushes remain visible in the journal.
    if ! grep -qxF 'Nothing to push - all store paths are already on Cachix.' "$push_log"; then
      cat "$push_log"
    fi
  done
  exec {candidates_fd}<&-
}

# Reconfigure cachix when the token file changes. Startup failures are fatal,
# but runtime refresh failures are left retryable so the service can keep
# running and pick up a repaired secret on a later poll.
refresh_cachix_auth_token() {
  local strict_mode=$1

  if [ ! -r "$CACHIX_AUTH_TOKEN_FILE" ] || [ ! -s "$CACHIX_AUTH_TOKEN_FILE" ]; then
    echo "[!] Missing or empty CACHIX_AUTH_TOKEN_FILE: $CACHIX_AUTH_TOKEN_FILE" >&2
    if [ "$strict_mode" = "strict" ]; then
      exit 10
    fi
    return 1
  fi

  local token_digest
  token_digest="$(sha256sum "$CACHIX_AUTH_TOKEN_FILE" | cut -d' ' -f1)"
  if [ "$token_digest" = "$CURRENT_CACHIX_TOKEN_DIGEST" ]; then
    return 0
  fi

  if ! cachix authtoken --stdin <"$CACHIX_AUTH_TOKEN_FILE"; then
    echo "[!] Failed to configure cachix auth token" >&2
    if [ "$strict_mode" = "strict" ]; then
      exit 11
    fi
    return 1
  fi

  CURRENT_CACHIX_TOKEN_DIGEST="$token_digest"
  echo "[+] Refreshed cachix auth token"
}

# Remove TMPDIR on exit
on_exit() {
  echo "[+] Stop (TMPDIR:$TMPDIR)"
  rm -fr "$TMPDIR"
}
trap on_exit EXIT

echo "[+] Start (TMPDIR=$TMPDIR)"

# Set cachix authentication token
mkdir -p "$CACHIX_STATE_DIR"
touch "$RETRY_FILE"
refresh_cachix_auth_token strict

# Initialize the persistent reference only once. This avoids losing queued
# paths across service restarts while still starting from the current store on
# first boot.
if [ ! -e "$REF_FILE" ]; then
  list_nix_store_paths "$REF_FILE"
  echo "[+] Initialized persistent reference"
fi

# Poll new store paths every 30 seconds
while sleep 30; do
  SKIP_POLL=0

  refresh_cachix_auth_token best-effort || true

  # Snapshot nix store paths for the current poll iteration
  list_nix_store_paths "$TMPDIR/snapshot"
  # Both files are sorted with LC_ALL=C, so comm can reliably emit only the
  # store paths that were added since the last reference snapshot.
  LC_ALL=C comm -13 "$REF_FILE" "$TMPDIR/snapshot" >"$TMPDIR/new"

  # Retry previously failed paths first, then append newly discovered store
  # paths.
  merge_candidates "$RETRY_FILE" "$TMPDIR/new" "$TMPDIR/candidates"

  # Rebuild the retry queue from the paths that still fail. Call bare so errexit
  # stays active inside the helper and everything it runs; an iteration that
  # could not finish is reported through SKIP_POLL instead of an exit status.
  process_candidates "$TMPDIR/candidates" "$TMPDIR/retry-next" "$TMPDIR/snapshot"
  if [ "$SKIP_POLL" -ne 0 ]; then
    continue
  fi

  # Persist the next retry queue before checking limits or advancing REF_FILE.
  mv -f "$TMPDIR/retry-next" "$RETRY_FILE"

  retry_file_size="$(wc -c <"$RETRY_FILE")"
  # Stop before advancing REF_FILE once the persisted retry queue becomes too
  # large, so operators can intervene without silently dropping failed paths.
  if [ "$retry_file_size" -gt "$RETRY_FILE_MAX_BYTES" ]; then
    echo "[!] Retry queue exceeded limit (${retry_file_size} > " \
      "${RETRY_FILE_MAX_BYTES}); refusing to advance reference" >&2
    exit 12
  fi

  # Always advance the reference after persisting retries. Paths that still
  # need uploading remain in RETRY_FILE; advancing REF_FILE prevents the same
  # "new" paths from being rediscovered and duplicated on every poll.
  # Write the new reference to a temporary file first so REF_FILE is replaced
  # atomically instead of being rewritten in place.
  cp -f "$TMPDIR/snapshot" "$TMPDIR/ref-update"
  mv -f "$TMPDIR/ref-update" "$REF_FILE"
done
