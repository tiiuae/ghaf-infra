#!/usr/bin/env bash
# shellcheck disable=SC2181,SC2059

# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -e # exit immediately if a command fails
set -u # treat unset variables as an error and exit
set -o pipefail # exit if any pipeline command fails

# This script is a helper to benchmark nix cache download

################################################################################

MYNAME=$(basename "$0")
TMPSTOREDIR="$(mktemp -d --suffix .nix.store)"
RED='' GREEN='' NONE=''

################################################################################

usage () {
    echo "Usage: $MYNAME [-h] [-v] [-o OUTFILE] -b BINCACHE -k KEY -f FLAKEREF "
    echo ""
    echo "Perform basic download test for the given binary cache."
    echo "The script attempts to download the FLAKEREF closure from the given"
    echo "binary cache, outputting the time the cache download took."
    echo "Script fails unless the full closure is available on the binary "
    echo "cache - it will not attempt to rebuild anything."
    echo "Script makes use of a temporary nix store so possible earlier cached"
    echo "content on the local nix store will not be used by the nix build"
    echo "command the script invokes."
    echo ""
    echo ""
    echo "Options:"
    echo " -h    Print this help message"
    echo " -v    Set the script verbosity to DEBUG"
    echo " -o    Set the script output file to OUTFILE"
    echo " -b    Set the target binary cache"
    echo " -k    Set the target binary cache trusted public key"
    echo " -f    Set the target flakeref - determines the closure (buildtime dependencies)"
    echo "       that will be downloaded from the target binary cache."
    echo ""
    echo "Example:"
    echo ""
    echo "  sudo ./$MYNAME \\"
    echo "    -f github:tiiuae/ghaf#packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64 \\"
    echo "    -b https://prod-cache.vedenemo.dev \\"
    echo "    -k 'prod-cache.vedenemo.dev~1:JcytRNMJJdYJVQCYwLNsrfVhct5dhCK2D3fa6O1WHOI='"
    echo ""
}

################################################################################

TRUSTED_SETTINGS_FILE="$HOME/.local/share/nix/trusted-settings.json"
disable_nix_trusted_settings () {
    # It seems there is no nix build option that would make nix ignore
    # the config from trusted-settings.json. Below is a hack to temporarily
    # remove the trusted-settings file during the execution of this script
    # to disable possible earlier defined trusted settings; such settings
    # might otherwise overwrite the nix build options we later manually
    # set in the nix build invocation.
    if [ -f "$TRUSTED_SETTINGS_FILE" ]; then
        mv -f "$TRUSTED_SETTINGS_FILE" "$TMPSTOREDIR/trusted.json"
    fi
}

on_exit () {
    if [ -f "$TMPSTOREDIR/trusted.json" ]; then
        mv -f "$TMPSTOREDIR/trusted.json" "$TRUSTED_SETTINGS_FILE"
    fi
    rm -fr "$TMPSTOREDIR"
}

print_err () {
    printf "${RED}Error:${NONE} %b\n" "$1" >&2
}

print_success () {
    printf "${GREEN}SUCCESS${NONE} ($(timer_stamp) sec)\n" >&2
    timer_begin
}

print_running () {
    printf "%-60b" "  $1 ... " >&2
}

argparse () {
    OPTIND=1; DEBUG="false"; OUTFILE="./cache-test.log";
    FLAKEREF=""; BINCACHE=""; KEY="";
    while getopts "hvf:b:k:o:" copt; do
        case "${copt}" in
            h)
                usage; exit 0 ;;
            v)
                DEBUG="true" ;;
            f)
                FLAKEREF="$OPTARG" ;;
            b)
                BINCACHE="$OPTARG" ;;
            k)
                KEY="$OPTARG" ;;
            o)
                OUTFILE="$OPTARG" ;;
            *)
                print_err "unrecognized option"; usage; exit 1 ;;
        esac
    done
    shift $((OPTIND-1))
    if [ -n "$*" ]; then
        print_err "unsupported positional argument(s): '$*'"; exit 1
    fi
    if [ -z "$BINCACHE" ]; then
        print_err "missing mandatory option (-b)"; usage; exit 1
    fi
    if [ -z "$KEY" ]; then
        print_err "missing mandatory option (-k)"; usage; exit 1
    fi
    if [ -z "$FLAKEREF" ]; then
        print_err "missing mandatory option (-f)"; usage; exit 1
    fi
}

exit_unless_command_exists () {
    if ! command -v "$1" &>/dev/null; then
        print_err "command '$1' is not installed (Hint: are you inside a nix-shell?)"
        exit 1
    fi
}

timer_begin () {
    TIMER_BEGIN=$(date +%s)
}

timer_stamp () {
    TIMER_NOW=$(date +%s)
    TIMER_ELAPSED=$(( TIMER_NOW - TIMER_BEGIN ))
    echo "$TIMER_ELAPSED"
}

################################################################################

test_nix_cache_info () {
    bincache="$1"
    print_running "${FUNCNAME[0]}"
    endpoint="$bincache/nix-cache-info"
    if ! curl -Ls "$endpoint" >/dev/null; then
        print_err "URL is not accessible: '$endpoint'"
        exit 1
    fi
    print_success
}

test_substitute_flakeref () {
    cache="$1"
    key="$2"
    flakeref="$3"
    print_running "${FUNCNAME[0]}"
    # Build using the given cache and key:
    # - Use temporary nix store so possible earlier cached content on the
    #   local nix store will not be used by the nix build command
    # - Together, the following two options make nix build fetch everything
    #   from the specified remote cache:
    #   - Set builders to '' so nothing will be built on remote builders
    #   - Set max-jobs to 0 so nothing will be built locally
    if ! nix build "$flakeref" \
      --no-accept-flake-config \
      --builders '' \
      --max-jobs 0 \
      --extra-trusted-substituters '' \
      --extra-trusted-public-keys '' \
      --substituters "$cache" \
      --trusted-substituters "$cache" \
      --trusted-public-keys "$key" \
      --store "$TMPSTOREDIR" \
      --verbose &> "$OUTFILE";
    then
        print_err "nix build failed, see build log in $OUTFILE"
        exit 1
    fi
    print_success
}

run_tests () {
    printf "\nTesting '$BINCACHE':\n"
    timer_begin
    test_nix_cache_info "$BINCACHE"
    test_substitute_flakeref "$BINCACHE" "$KEY" "$FLAKEREF"
}

################################################################################

main () {
    trap on_exit EXIT
    # Colorize output if stdout is to a terminal (and not to pipe or file)
    if [ -t 1 ]; then
      RED='\033[1;31m'
      GREEN='\033[1;32m'
      NONE='\033[0m'
    fi
    argparse "$@"
    if [ ! "$(id -u)" = "0" ]; then
        print_err "This script needs to be run with sudo"
        exit
    fi
    if [ "$DEBUG" = "true" ]; then
        set -x
    fi
    exit_unless_command_exists nix
    exit_unless_command_exists date
    exit_unless_command_exists mktemp
    disable_nix_trusted_settings
    run_tests
}

main "$@"

################################################################################
