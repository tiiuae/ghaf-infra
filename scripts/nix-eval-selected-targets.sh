#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -e
set -E
set -u
set -o pipefail

TMPDIR="$(mktemp -d --suffix .nix-eval-jobs)"
MYNAME=$(basename "$0")

usage() {
  cat <<EOF

Usage: $MYNAME [-h] [-f FLAKE_REF] -t TARGETS_FILE

Evaluate the selected flake outputs with nix-eval-jobs.

Options:
 -h    Print this help message.
 -f    Flake reference to evaluate. Defaults to '.#'.
 -t    Text file containing one target attribute per line.

Example TARGETS_FILE content:
  packages.x86_64-linux.doc
  packages.x86_64-linux.lenovo-x1-carbon-gen11-debug

EOF
}

on_exit() {
  rm -rf "$TMPDIR"
}

argparse() {
  FLAKE_REF=".#"
  TARGETS_FILE=""

  OPTIND=1
  while getopts "hf:t:" copt; do
    case "${copt}" in
    h)
      usage
      exit 0
      ;;
    f)
      FLAKE_REF="$OPTARG"
      ;;
    t)
      TARGETS_FILE="$OPTARG"
      ;;
    *)
      usage >&2
      exit 1
      ;;
    esac
  done
  shift $((OPTIND - 1))

  if [ -n "$*" ]; then
    printf 'Error: unsupported positional argument(s): %s\n' "$*" >&2
    exit 1
  fi
  if [ -z "$TARGETS_FILE" ]; then
    printf 'Error: -t TARGETS_FILE is required\n' >&2
    exit 1
  fi
  if [ ! -f "$TARGETS_FILE" ]; then
    printf 'Error: targets file not found: %s\n' "$TARGETS_FILE" >&2
    exit 1
  fi
}

build_select_expr() {
  local target_specs_file="$1"
  local target_specs_json
  local target_specs_nix_string

  target_specs_json=$(tr -d '\n' <"$target_specs_file")
  target_specs_nix_string=$(printf '%s' "$target_specs_json" | jq -Rs '.')

  cat >"$TMPDIR/select.nix" <<EOF
flake:
let
  lib = flake.inputs.nixpkgs.lib;
  targetSpecs = builtins.fromJSON ${target_specs_nix_string};
  selectTarget = target:
    lib.setAttrByPath target.path (
      lib.attrByPath target.path (throw "Build target \${target.attr} missing from flake outputs") flake
    );
in
  builtins.foldl' (acc: target: lib.recursiveUpdate acc (selectTarget target)) {} targetSpecs
EOF
}

prepare_targets() {
  jq -Rsc '
    split("\n")
    | map(select(length > 0))
    | map({ attr: ., path: split(".") })
  ' "$TARGETS_FILE" >"$TMPDIR/targets.json"

  if [ "$(jq 'length' "$TMPDIR/targets.json")" -eq 0 ]; then
    printf 'Error: no targets provided\n' >&2
    exit 1
  fi
}

print_target_summary() {
  local target_count
  target_count=$(jq 'length' "$TMPDIR/targets.json")

  printf '[+] Evaluating %s selected targets with nix-eval-jobs\n' "$target_count"
  jq -r '.[].attr | "  - " + .' "$TMPDIR/targets.json"
}

render_results() {
  local start_time="$1"
  local line
  local attr

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    printf '%s\n' "$line" >>"$TMPDIR/results.ndjson"

    attr=$(printf '%s\n' "$line" | jq -r '.attr // "?"')
    if printf '%s\n' "$line" | jq -e 'has("error")' >/dev/null; then
      printf '[%6ss] FAIL %s\n' "$((SECONDS - start_time))" "$attr"
      printf '%s\n' "$line" | jq -r '.error'
    else
      printf '[%6ss] OK   %s\n' "$((SECONDS - start_time))" "$attr"
    fi
  done
}

heartbeat() {
  local eval_pid="$1"
  local start_time="$2"
  local target_count="$3"
  local emitted_count

  while kill -0 "$eval_pid" 2>/dev/null; do
    sleep 30
    if ! kill -0 "$eval_pid" 2>/dev/null; then
      break
    fi

    emitted_count=$(wc -l <"$TMPDIR/results.ndjson")
    printf '[%6ss] still evaluating, %s/%s results emitted\n' \
      "$((SECONDS - start_time))" "$emitted_count" "$target_count"
  done
}

run_eval() {
  local start_time
  local target_count
  local success_count
  local error_count
  local eval_status
  local eval_pid
  local heartbeat_pid
  local select_expr

  start_time=$SECONDS
  target_count=$(jq 'length' "$TMPDIR/targets.json")
  : >"$TMPDIR/results.ndjson"
  select_expr=$(tr '\n' ' ' <"$TMPDIR/select.nix")

  print_target_summary

  nix-eval-jobs \
    --flake "$FLAKE_REF" \
    --select "$select_expr" \
    --force-recurse \
    --option allow-import-from-derivation false |
    render_results "$start_time" &
  eval_pid=$!

  heartbeat "$eval_pid" "$start_time" "$target_count" &
  heartbeat_pid=$!

  if wait "$eval_pid"; then
    eval_status=0
  else
    eval_status=$?
  fi

  kill "$heartbeat_pid" 2>/dev/null || true
  wait "$heartbeat_pid" 2>/dev/null || true

  success_count=$(jq -r 'select(has("error") | not) | .attr' "$TMPDIR/results.ndjson" | wc -l)
  error_count=$(jq -r 'select(has("error")) | .attr' "$TMPDIR/results.ndjson" | wc -l)

  printf '[%6ss] Completed evaluation: %s succeeded, %s failed\n' \
    "$((SECONDS - start_time))" "$success_count" "$error_count"

  if [ "$eval_status" -ne 0 ] && [ "$error_count" -eq 0 ]; then
    printf 'Error: nix-eval-jobs exited with status %s\n' "$eval_status" >&2
    exit "$eval_status"
  fi

  if [ "$error_count" -ne 0 ]; then
    printf 'Error: nix-eval-jobs reported evaluation failures\n' >&2
    exit 1
  fi
}

main() {
  trap on_exit EXIT

  argparse "$@"
  prepare_targets
  build_select_expr "$TMPDIR/targets.json"
  run_eval
}

main "$@"
