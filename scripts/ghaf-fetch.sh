#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

MYNAME="${0##*/}"

usage() {
  cat <<EOF
Usage: $MYNAME [--all | --primary | --referrer ARTIFACT_TYPE] OCI_REFERENCE

Pull OCI_REFERENCE and referrers returned by 'oras discover' into the current
directory after selecting the artifact and referrers interactively with gum.
The selector shows org.opencontainers.image.description when available. With
--all, pull OCI_REFERENCE and all referrers without requiring an interactive
terminal. --primary pulls only the primary artifact and its manifest. --referrer
pulls only referrers with the specified artifact type. Both are noninteractive.

Example:

  $MYNAME registry.vedenemo.dev/ghaf/job/target:tag
  $MYNAME registry.vedenemo.dev/ghaf/job/target@sha256:...
  $MYNAME --all registry.vedenemo.dev/ghaf/job/target:tag
  $MYNAME --primary registry.vedenemo.dev/ghaf/job/target:tag
  $MYNAME --referrer application/vnd.ghaf.release-attestation.v1+json registry.vedenemo.dev/ghaf/job/target:tag

EOF
}

main() {
  if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
    usage
    exit 0
  fi

  pull_mode=interactive
  referrer_type=""
  case "${1:-}" in
  --all | --primary)
    pull_mode="${1#--}"
    shift
    ;;
  --referrer)
    if [[ $# -lt 3 || -z $2 ]]; then
      usage
      exit 1
    fi
    pull_mode=referrer
    referrer_type="$2"
    shift 2
    ;;
  esac

  if [ "$#" -ne 1 ]; then
    usage
    exit 1
  fi

  if [ "$pull_mode" = interactive ] && { ! [ -t 0 ] || ! [ -t 1 ]; }; then
    printf "Error: interactive terminal required\n" >&2
    exit 1
  fi

  reference="$1"
  repository="$reference"

  if [[ $repository == *@* ]]; then
    repository="${repository%@*}"
  elif [[ ${repository##*/} == *:* ]]; then
    repository="${repository%:*}"
  fi

  discovery='{"referrers":[]}'
  if [ "$pull_mode" != primary ]; then
    printf "[+] Discovering referrers...\n"
    discovery="$(
      oras discover \
        --distribution-spec v1.1-referrers-api \
        --depth 1 \
        --format json \
        "$reference"
    )"
  fi

  printf "[+] Fetching artifact metadata...\n"
  manifest="$(oras manifest fetch --format json "$reference")"
  digest="$(oras resolve "$reference")"
  config_digest="$(
    printf "%s\n" "$manifest" |
      jq -r '.content.config.digest // empty'
  )"
  artifact_name="${reference##*/}"
  artifact_name="${artifact_name%@*}"
  artifact_name="${artifact_name%%:*}"

  artifact_label="$(
    printf "%s\n" "$manifest" |
      jq -r --arg fallback "$artifact_name" '
        .content.annotations["org.opencontainers.image.description"]
        // .content.layers[0].annotations["org.opencontainers.image.description"]
        // .content.annotations["org.opencontainers.image.title"]
        // .content.layers[0].annotations["org.opencontainers.image.title"]
        // .content.artifactType
        // $fallback
        | gsub("[\t\r\n]+"; " ")
      '
  )"

  choices="$(
    if [ "$pull_mode" != referrer ]; then
      printf "%s | %s\n" "$artifact_label" "$digest"
      if [ -n "$config_digest" ]; then
        printf "Manifest | %s\n" "$config_digest"
      fi
    fi
    printf "%s\n" "$discovery" |
      jq -r --arg type "$referrer_type" '
        .referrers[]?
        | select(.digest)
        | select($type == "" or .artifactType == $type)
        | [
            (
              .annotations["org.opencontainers.image.description"]
              // .annotations["org.opencontainers.image.title"]
              // .artifactType
              // "referrer"
              | gsub("[\t\r\n]+"; " ")
            ),
            .digest
          ]
        | join(" | ")
      '
  )"

  if [ "$pull_mode" != interactive ]; then
    selected="$choices"
  else
    selected="$(printf "%s\n" "$choices" | gum choose --no-limit --header "Select artifacts to pull")"
  fi

  if [ -z "$selected" ]; then
    printf "[+] No artifacts selected\n"
    return 0
  fi

  while IFS= read -r selected_artifact; do
    selected_digest="${selected_artifact##* | }"
    pull_reference="$repository@$selected_digest"

    printf "[+] Pulling: %s\n" "$pull_reference"
    if [ "$selected_digest" = "$config_digest" ]; then
      oras blob fetch --output manifest.json "$pull_reference"
    else
      oras pull "$pull_reference"
    fi
  done <<<"$selected"
}

main "$@"
