#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -e # exit immediately if a command fails
set -u # treat unset variables as an error and exit
set -o pipefail # exit if any pipeline command fails

# This script is a helper to recursively download a URL

################################################################################

MYNAME=$(basename "$0")
RED='' NONE=''
OUTDIR="get-artifacts-out"

################################################################################

usage () {
    echo "Usage: $MYNAME [-h] [-v] [-o OUTDIR] -u URL"
    echo ""
    echo "Recursively fetch URL to a local directory (OUTDIR)"
    echo ""
    echo ""
    echo "Options:"
    echo " -h    Print this help message"
    echo " -v    Set the script verbosity to DEBUG"
    echo " -o    Set the script output directory to OUTDIR (default: ./$OUTDIR)"
    echo " -u    Target URL to recursively download"
    echo ""
    echo "Example:"
    echo ""
    echo "  ./$MYNAME -u https://ghaf-jenkins-controller-dev.azure.com/path/to/artifact/"
    echo ""
}

################################################################################

print_err () {
    printf "${RED}Error:${NONE} %b\n" "$1" >&2
}

argparse () {
    OPTIND=1; DEBUG="false"; URL="";
    while getopts "hvu:o:" copt; do
        case "${copt}" in
            h)
                usage; exit 0 ;;
            v)
                DEBUG="true" ;;
            o)
                OUTDIR="$OPTARG" ;;
            u)
                URL="$OPTARG" ;;
            *)
                print_err "unrecognized option"; usage; exit 1 ;;
        esac
    done
    shift $((OPTIND-1))
    if [ -n "$*" ]; then
        print_err "unsupported positional argument(s): '$*'"; exit 1
    fi
    if [ -z "$URL" ]; then
        print_err "missing mandatory option (-u)"; usage; exit 1
    fi
}

exit_unless_command_exists () {
    if ! command -v "$1" &>/dev/null; then
        print_err "command '$1' is not installed (Hint: are you inside a nix-shell?)"
        exit 1
    fi
}

exit_unless_valid_url () {
    url="$1"
    if ! wget --quiet --server-response --spider "$url/" >/dev/null 2>&1; then
        print_err "invalid URL: '$url'"
        exit 1
    fi
}

get_recursively () {
    url="$1"
    outdir="$2"
    # If we got this far, we know the URL is valid. Recursive wget downloads
    # might still fail, due to some wget scraped content not being available
    # on the remote. In such cases, wget will also exit with error status,
    # even though it was able to download all the content we care about.
    # We don't want to abort the whole script execution if that happens
    # which is why we need to ignore the error status '8' i.e.
    # "Server issued an error response":
    set +e
    wget \
        --recursive \
        --no-parent \
        --level=inf \
        --timestamping \
        --no-if-modified-since \
        --continue \
        --execute robots=off \
        --reject 'index.html?*' \
        --user-agent=Mozilla/5.0 \
        --accept '*' \
        --random-wait \
        --no-host-directories \
        --directory-prefix="$outdir" \
        --quiet --show-progress --progress=bar:force \
        "$url/";
    wget_ret="$?"
    set -e
    if [  "$wget_ret" != "0" ] && [ "$wget_ret" != "8" ]; then
        print_err "wget exit with error status: '$wget_ret'"
        exit 1
    fi
}

tar_subdirs () {
    outdir="$1"
    find "$outdir" -type d -name 'build_*-commit_*' | while read -r build_dir;
    do
        find "$build_dir" -type d -mindepth 1 -maxdepth 1 | while read -r target_dir;
        do
            target_reldir="$(basename "$target_dir")"
            tar -cf "${target_dir}.tar" -C "$build_dir" "$target_reldir"
        done
    done
}

################################################################################

main () {
    # Colorize output if stdout is to a terminal (and not to pipe or file)
    if [ -t 1 ]; then
      RED='\033[1;31m'
      NONE='\033[0m'
    fi
    argparse "$@"
    if [ "$DEBUG" = "true" ]; then
        set -x
    fi
    exit_unless_command_exists wget
    exit_unless_command_exists tar
    exit_unless_valid_url "$URL"
    get_recursively "$URL" "$OUTDIR"
    tar_subdirs "$OUTDIR"
    printf "\nWrote: '%s'\n" "$(readlink -f "$OUTDIR")"
}

main "$@"

################################################################################
