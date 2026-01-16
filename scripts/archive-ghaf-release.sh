#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -e          # exit immediately if a command fails
set -E          # exit immediately if a command fails (subshells)
set -u          # treat unset variables as an error and exit
set -o pipefail # exit if any pipeline command fails

# This script is a helper to archive a ghaf release

################################################################################

TMPDIR="$(mktemp -d --suffix .tmpbuild)"
MYNAME=$(basename "$0")
RED='' NONE=''

# Expected arguments and their defaults if not passed in environment
# variables. We intentionally don't want these variables to be command-line
# options.
STORAGE_URL="${STORAGE_URL:=https://hel1.your-objectstorage.com}"
BUCKET="${BUCKET:=ghaf-artifacts-dev}"
ACCESS_KEY="${ACCESS_KEY:=}"
SECRET_KEY="${SECRET_KEY:=}"

################################################################################

usage() {
  cat <<EOF
Usage: $MYNAME [-h] [-v] -a ARTIFACTS

Archive Ghaf release to a permanent storage.
Assumes storage credentials are exported in environment variables ACCESS_KEY and SECRET_KEY.


Options:
  -h    Print this help message
  -v    Set the script verbosity to DEBUG
  -a    Specify a path to ARTIFACTS directory
  -t    Specify a ghaf release tag/version name, e.g. 'ghaf-25.12.1'


Examples:

  Archive artifacts from the given path:
    $ ./$MYNAME -t ghaf-25.12.1 -a /local/path/to/artifacts/

EOF
}

################################################################################

print_err() {
  printf "${RED}Error:${NONE} %b\n" "$1" >&2
}

on_exit() {
  echo "[+] Removing tmpdir: '$TMPDIR'"
  rm -fr "$TMPDIR"
}

argparse() {
  OPTIND=1
  DEBUG="false"
  ARTIFACTS=""
  GHAF_VERSION=""
  while getopts "hva:t:" copt; do
    case "${copt}" in
    h)
      usage
      exit 0
      ;;
    v)
      DEBUG="true"
      ;;
    a)
      ARTIFACTS="$OPTARG"
      ;;
    t)
      GHAF_VERSION="$OPTARG"
      ;;
    *)
      print_err "unrecognized option"
      usage
      exit 1
      ;;
    esac
  done
  shift $((OPTIND - 1))
  if [ -n "$*" ]; then
    print_err "unsupported positional argument(s): '$*'"
    exit 1
  fi
  if [ -z "$ARTIFACTS" ]; then
    print_err "missing mandatory option (-a)"
    usage
    exit 1
  fi
  if [ -z "$GHAF_VERSION" ]; then
    echo "missing mandatory option (-t)"
    usage
    exit 1
  fi
  if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    print_err "missing storage credential environment variables"
    usage
    exit 1
  fi
  if [ ! -d "$ARTIFACTS" ]; then
    print_err "invalid ARTIFACTS directory path (-a)"
    usage
    exit 1
  fi
}

exit_unless_command_exists() {
  if ! command -v "$1" &>/dev/null; then
    print_err "command '$1' is not installed (Hint: are you inside a nix-shell?)"
    exit 1
  fi
}

verify_signatures() {
  dir="$1"
  img=$(find -L "$dir" -regextype egrep -regex '.*\.(img|iso|zst)' -print -quit)
  if [ -z "$img" ]; then
    print_err "missing image: $dir"
    exit 1
  fi
  img_sig=$(find -L "$dir" -name "$(basename "$img").sig" -print -quit)
  if [ -z "$img_sig" ]; then
    print_err "missing image signature: $dir"
    exit 1
  fi
  prov=$(find -L "$dir" -name "provenance.json" -print -quit)
  if [ -z "$prov" ]; then
    print_err "missing provenance file: $dir"
    exit 1
  fi
  prov_sig=$(find -L "$dir" -name "provenance.json.sig" -print -quit)
  if [ -z "$prov_sig" ]; then
    print_err "missing provenance esignature: $dir"
    exit 1
  fi
  echo "[+] Verifying: $img"
  if ! verify-signature image "$img" "$img_sig"; then
    print_err "failed verifying image signature"
    print_err "  image: $img"
    print_err "  signature: $img_sig"
    exit 1
  fi
  if ! verify-signature provenance "$prov" "$prov_sig"; then
    print_err "failed verifying provenance signature"
    print_err "  provenance: $prov"
    print_err "  signature: $prov_sig"
    exit 1
  fi
}

prepare_artifacts() {
  build_targets=(
    # Leading and trailing spaces are intentional
    " packages.aarch64-linux.nvidia-jetson-orin-agx-debug "
    " packages.aarch64-linux.nvidia-jetson-orin-nx-debug "
    " packages.x86_64-linux.lenovo-x1-carbon-gen11-debug "
    " packages.x86_64-linux.lenovo-x1-carbon-gen11-debug-installer "
    " packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64 "
    " packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64 "
    " packages.x86_64-linux.system76-darp11-b-debug "
    " packages.x86_64-linux.system76-darp11-b-debug-installer "
  )
  artifactsdir="$1"
  for dir in "$artifactsdir"/*/; do
    target_name="$(basename "$dir")"
    # Skip unless target_name is listed in the build_targets list
    if ! echo "${build_targets[@]}" | grep -P -q " $target_name "; then
      continue
    fi
    echo "[+] Release artifact: $target_name"
    # build output
    mkdir -p "$TMPDIR/$target_name"
    ln -s "$dir" "$TMPDIR/$target_name/build"
    # scs output
    if [ -d "$artifactsdir/scs/$target_name" ]; then
      ln -s "$artifactsdir/scs/$target_name" "$TMPDIR/$target_name/scs"
    fi
    # verify signatures
    verify_signatures "$TMPDIR/$target_name"
    # test-results output
    if [ -d "$artifactsdir/test-results/$target_name" ]; then
      ln -s "$artifactsdir/test-results/$target_name" "$TMPDIR/$target_name/test-results"
    fi
    # uefisigned output
    if [ -d "$artifactsdir/uefisigned/$target_name" ]; then
      ln -s "$artifactsdir/uefisigned/$target_name" "$TMPDIR/$target_name/uefisigned"
    fi
    # Create a release tarball
    tarball=${target_name#"packages."} # strip possible 'packages.' prefix
    mkdir -p "$TMPDIR/archived"
    tar -h -c -f "$TMPDIR/archived/$tarball.tar" -C "$TMPDIR" "$target_name"
  done
  echo "[+] Release content:"
  tree --noreport -I archived -l "$TMPDIR"
  echo "[+] Release archive:"
  tree --noreport "$TMPDIR/archived"
  if [ ! -d "$TMPDIR/archived" ]; then
    print_err "nothing to archive"
    exit 1
  fi
}

################################################################################

main() {
  # Colorize output if stdout is to a terminal (and not to pipe or file)
  if [ -t 1 ]; then
    RED='\033[1;31m'
    NONE='\033[0m'
  fi
  argparse "$@"
  if [ "$DEBUG" = "true" ]; then set -x; fi
  trap on_exit EXIT
  exit_unless_command_exists mc
  exit_unless_command_exists tar
  exit_unless_command_exists realpath
  exit_unless_command_exists tree

  # Prepare the release archive from artifacts
  prepare_artifacts "$(realpath "$ARTIFACTS")"

  # Upoload the archive to Hetzner
  echo "[+] Uploading release tar archives to Hetzner"
  mc alias set hetzner "$STORAGE_URL" "$ACCESS_KEY" "$SECRET_KEY" >/dev/null
  mc mirror "$TMPDIR/archived" "hetzner/$BUCKET/$GHAF_VERSION"
}

main "$@"

################################################################################
