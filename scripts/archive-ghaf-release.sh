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
OCI_REPOSITORY_PREFIX="${OCI_REPOSITORY_PREFIX:=registry.vedenemo.dev/ghaf/release-candidate}"

release_targets=(
  "packages.aarch64-linux.nvidia-jetson-orin-agx-debug"
  "packages.aarch64-linux.nvidia-jetson-orin-nx-debug"
  "packages.x86_64-linux.intel-laptop-debug"
  "packages.x86_64-linux.intel-laptop-debug-installer"
  "packages.x86_64-linux.intel-laptop-storeDisk-debug-installer"
  "packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64"
  "packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64"
)

################################################################################

usage() {
  cat <<EOF
Usage: $MYNAME [-h] [-v] (-a ARTIFACTS | -o OCI_TAG) -t GHAF_VERSION

Archive Ghaf release to a permanent storage.
Assumes storage credentials are exported in environment variables ACCESS_KEY and SECRET_KEY.


Options:
  -h    Print this help message
  -v    Set the script verbosity to DEBUG
  -a    Specify a path to ARTIFACTS directory
  -o    Specify an OCI tag to pull release artifacts from the registry
  -t    Specify a ghaf release tag/version name, e.g. 'ghaf-25.12.1'


Examples:

  Archive artifacts from the given path:
    $ ./$MYNAME -t ghaf-25.12.1 -a /local/path/to/artifacts/

  Archive artifacts from an OCI registry tag:
    $ ./$MYNAME -t ghaf-25.12.1 -o release-20260603_123242705-29e9ef6e98ef9a589b5814fe438ba94601df1bdc

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
  OCI_TAG=""
  GHAF_VERSION=""
  while getopts "hva:o:t:" copt; do
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
    o)
      OCI_TAG="$OPTARG"
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
  if [[ -n $* ]]; then
    print_err "unsupported positional argument(s): '$*'"
    exit 1
  fi
  if [[ -z $ARTIFACTS && -z $OCI_TAG ]]; then
    print_err "missing mandatory option (-a or -o)"
    usage
    exit 1
  fi
  if [[ -n $ARTIFACTS && -n $OCI_TAG ]]; then
    print_err "options -a and -o are mutually exclusive"
    usage
    exit 1
  fi
  if [[ -z $GHAF_VERSION ]]; then
    echo "missing mandatory option (-t)"
    usage
    exit 1
  fi
  if [[ -z $ACCESS_KEY || -z $SECRET_KEY ]]; then
    print_err "missing storage credential environment variables"
    usage
    exit 1
  fi
  if [[ -n $ARTIFACTS && ! -d $ARTIFACTS ]]; then
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

is_release_target() {
  candidate="$1"
  for target in "${release_targets[@]}"; do
    if [[ $candidate == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

verify_signatures() {
  dir="$1"
  manifest="$dir/manifest.json"

  if [[ ! -f $manifest ]]; then
    print_err "missing manifest: $dir"
    exit 1
  fi
  if ! img_rel=$(jq -re '.image.path' "$manifest"); then
    print_err "missing image entry in manifest: $manifest"
    exit 1
  fi
  img="$dir/$img_rel"
  if [[ -z $img_rel ]]; then
    print_err "missing image: $dir"
    exit 1
  fi
  if ! img_sig_rel=$(jq -re '.image.signature.path' "$manifest"); then
    print_err "missing image signature entry in manifest: $manifest"
    exit 1
  fi
  img_sig="$dir/$img_sig_rel"
  if [[ -z $img_sig_rel ]]; then
    print_err "missing image signature: $dir"
    exit 1
  fi
  if ! prov_rel=$(jq -re '.attestations.provenance.path' "$manifest"); then
    print_err "missing provenance entry in manifest: $manifest"
    exit 1
  fi
  prov="$dir/$prov_rel"
  if [[ -z $prov_rel ]]; then
    print_err "missing nix_build provenance file: $dir"
    exit 1
  fi
  if ! prov_sig_rel=$(jq -re '.attestations.provenance.signature.path' "$manifest"); then
    print_err "missing provenance signature entry in manifest: $manifest"
    exit 1
  fi
  prov_sig="$dir/$prov_sig_rel"
  if [[ -z $prov_sig_rel ]]; then
    print_err "missing nix_build provenance signature: $dir"
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

pull_artifacts_from_oci() {
  tag="$1"
  artifactsdir="$TMPDIR/oci-artifacts"

  if [[ $tag == */* || $tag == *@* || $tag == *:* ]]; then
    print_err "OCI release archival requires a tag, not a reference: $tag"
    exit 1
  fi

  mkdir -p "$artifactsdir"
  pulled_targets=0
  for target_name in "${release_targets[@]}"; do
    oci_target_name="${target_name#packages.}"
    oci_target_name="${oci_target_name,,}"
    target_reference="$OCI_REPOSITORY_PREFIX/$oci_target_name:$tag"
    target_dir="$artifactsdir/$target_name"

    mkdir -p "$target_dir"
    echo "[+] Pulling release artifacts from OCI: $target_reference"
    manifest_log="$target_dir/oras-manifest-fetch.log"
    if ! resolved_digest=$(oras resolve "$target_reference" 2>"$manifest_log"); then
      if grep -Eiq "(not found|manifest unknown|name unknown)" "$manifest_log"; then
        echo "[+] Skipping missing OCI target: $target_reference"
        rm -rf "$target_dir"
        continue
      fi
      cat "$manifest_log" >&2
      print_err "failed checking OCI target: $target_reference"
      exit 1
    fi
    rm -f "$manifest_log"
    resolved_reference="$OCI_REPOSITORY_PREFIX/$oci_target_name@$resolved_digest"
    printf '%s\n' "$resolved_reference" >"$target_dir/oci-reference"

    if ! (
      cd "$target_dir"
      ghaf-fetch --all "$resolved_reference"
    ); then
      print_err "failed pulling OCI target: $resolved_reference"
      exit 1
    fi

    manifest="$target_dir/manifest.json"
    if [[ ! -f $manifest ]]; then
      print_err "missing manifest pulled from OCI reference: $resolved_reference"
      exit 1
    fi

    if ! manifest_target=$(jq -re '.target' "$manifest"); then
      print_err "missing target entry in OCI manifest: $manifest"
      exit 1
    fi
    if [[ $manifest_target != "$target_name" ]]; then
      print_err "unexpected target in OCI manifest: expected '$target_name', got '$manifest_target'"
      exit 1
    fi

    if [[ -f "$target_dir/test-results.tar" ]]; then
      tar -xf "$target_dir/test-results.tar" -C "$target_dir"
      rm -f "$target_dir/test-results.tar"
    fi
    pulled_targets=$((pulled_targets + 1))
  done

  if [[ $pulled_targets -eq 0 ]]; then
    print_err "no release targets found in OCI registry for tag: $tag"
    exit 1
  fi

  ARTIFACTS="$artifactsdir"
}

tag_oci_release_artifacts() {
  for dir in "$ARTIFACTS"/*/; do
    target_name="$(basename "$dir")"
    if ! is_release_target "$target_name"; then
      continue
    fi

    source_reference_file="$dir/oci-reference"
    if [[ ! -f $source_reference_file ]]; then
      print_err "missing resolved OCI reference for release artifact: $target_name"
      exit 1
    fi
    source_reference="$(<"$source_reference_file")"

    echo "[+] Tagging OCI release artifact: $source_reference"
    oras manifest fetch --registry-config "$OCI_REGISTRY_CONFIG" "$source_reference" >/dev/null
    oras tag \
      --registry-config "$OCI_REGISTRY_CONFIG" \
      "$source_reference" \
      "$GHAF_VERSION" \
      ghaf-latest
  done
}

prepare_artifacts() {
  artifactsdir="$1"
  for dir in "$artifactsdir"/*/; do
    target_name="$(basename "$dir")"
    # Skip unless target_name is listed in the release target list
    if ! is_release_target "$target_name"; then
      continue
    fi
    echo "[+] Release artifact: $target_name"
    manifest="$dir/manifest.json"

    # verify signatures
    verify_signatures "$dir"

    mkdir -p "$TMPDIR/$target_name"
    ln -s "$manifest" "$TMPDIR/$target_name/manifest.json"

    if ! image=$(jq -re '.image.path' "$manifest"); then
      print_err "missing image entry in manifest: $manifest"
      exit 1
    fi
    if ! image_sig=$(jq -re '.image.signature.path' "$manifest"); then
      print_err "missing image signature entry in manifest: $manifest"
      exit 1
    fi

    # build output
    ln -s "$dir/$image" "$TMPDIR/$target_name/$image"
    ln -s "$dir/$image_sig" "$TMPDIR/$target_name/$image_sig"

    # attestations
    if [[ -d "$dir/attestations" ]]; then
      ln -s "$dir/attestations" "$TMPDIR/$target_name/attestations"
    fi

    # test-results output
    if [[ -d "$dir/test-results" ]]; then
      ln -s "$dir/test-results" "$TMPDIR/$target_name/test-results"
    fi
    if [[ -f "$dir/test-results.json" ]]; then
      ln -s "$dir/test-results.json" "$TMPDIR/$target_name/test-results.json"
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
  if [[ ! -d "$TMPDIR/archived" ]]; then
    print_err "nothing to archive"
    exit 1
  fi
}

################################################################################

main() {
  # Colorize output if stdout is to a terminal (and not to pipe or file)
  if [[ -t 1 ]]; then
    RED='\033[1;31m'
    NONE='\033[0m'
  fi
  argparse "$@"
  if [[ $DEBUG == "true" ]]; then set -x; fi
  trap on_exit EXIT
  exit_unless_command_exists mc
  exit_unless_command_exists tar
  exit_unless_command_exists realpath
  exit_unless_command_exists tree
  exit_unless_command_exists jq

  # Prepare the release archive from artifacts
  if [[ -n $OCI_TAG ]]; then
    if [[ -z ${OCI_PASSWORD:-} ]]; then
      print_err "OCI_PASSWORD is required when tagging release artifacts"
      exit 1
    fi
    exit_unless_command_exists oras
    exit_unless_command_exists ghaf-fetch
    OCI_REGISTRY_CONFIG="$TMPDIR/oras-auth/config.json"
    mkdir -p "${OCI_REGISTRY_CONFIG%/*}"
    printf '%s\n' "$OCI_PASSWORD" | oras login \
      -u "${OCI_USERNAME:-jenkins}" \
      --password-stdin \
      --registry-config "$OCI_REGISTRY_CONFIG" \
      "${OCI_REPOSITORY_PREFIX%%/*}"
    pull_artifacts_from_oci "$OCI_TAG"
  else
    ARTIFACTS="$(realpath "$ARTIFACTS")"
  fi
  prepare_artifacts "$ARTIFACTS"

  # Upoload the archive to Hetzner
  echo "[+] Uploading release tar archives to Hetzner"
  mc alias set hetzner "$STORAGE_URL" "$ACCESS_KEY" "$SECRET_KEY" >/dev/null
  mc mirror "$TMPDIR/archived" "hetzner/$BUCKET/$GHAF_VERSION"

  if [[ -n $OCI_TAG ]]; then
    tag_oci_release_artifacts
  fi
}

main "$@"

################################################################################
