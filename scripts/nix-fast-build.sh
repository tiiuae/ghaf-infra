#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

################################################################################

# This script is a helper to run nix-fast-build for ghaf-infra.

# https://www.gnu.org/software/parallel/env_parallel.html
# shellcheck source=/dev/null
source env_parallel.bash
env_parallel --session

set -e # exit immediately if a command fails
set -u # treat unset variables as an error and exit
set -o pipefail # exit if any pipeline command fails

MYNAME=$(basename "$0")
RED='' NONE=''
DEF_BUILDER="builder.vedenemo.dev"

################################################################################

usage () {
    echo ""
    echo "Usage: $MYNAME [-h] [-v] [-o OPTS] [-t TARGET]"
    echo ""
    echo "Helper to run nix-fast-build for ghaf-infra"
    echo ""
    echo "Options:"
    echo " -t    Build selector - supported values are 'x86' and 'aarch' (default='x86')"
    echo " -o    Options passed directly to nix-fast-build. See available options at:"
    echo "       https://github.com/Mic92/nix-fast-build#reference"
    echo " -v    Set the script verbosity to DEBUG"
    echo " -h    Print this help message"
    echo ""
    echo "Examples:"
    echo ""
    echo "  Following command builds all ghaf-infra 'x86' targets on the default"
    echo "  remote builder ($DEF_BUILDER) authenticating as current user:"
    echo ""
    echo "  $ $MYNAME -t x86"
    echo ""
    echo ""
    echo "  Following command builds all 'aarch' targets on the specified"
    echo "  remote builder 'my_builder' authenticating as user 'foo' with"
    echo "  ssh key '~/.ssh/my_key':"
    echo ""
    echo "  $ $MYNAME -t aarch -o '--remote foo@my_builder --remote-ssh-option IdentityFile ~/.ssh/my_key'"
    echo ""
}

################################################################################

print_err () {
    printf "${RED}Error:${NONE} %b\n" "$1" >&2
}

argparse () {
    # Colorize output if stdout is to a terminal (and not to pipe or file)
    if [ -t 1 ]; then RED='\033[1;31m'; NONE='\033[0m'; fi
    # Parse arguments
    DEBUG="false"; OPTS="--remote $DEF_BUILDER"; TARGET="x86";
    OPTIND=1
    while getopts "hvo:t:" copt; do
        case "${copt}" in
            h)
                usage; exit 0 ;;
            v)
                DEBUG="true" ;;
            o)
                OPTS="$OPTARG" ;;
            t)
                TARGET="$OPTARG" ;;
            *)
                print_err "unrecognized option"; usage; exit 1 ;;
        esac
    done
    shift $((OPTIND-1))
    if [ -n "$*" ]; then
        print_err "unsupported positional argument(s): '$*'"; exit 1
    fi
}

exit_unless_command_exists () {
    if ! command -v "$1" &>/dev/null; then
        print_err "command '$1' is not installed (Hint: are you inside a nix-shell?)"
        exit 1
    fi
}

################################################################################

nix_fast_build () {
    target="$1"
    tfmt="%H:%M:%S"
    [ "$DEBUG" = "true" ] && set -x
    echo ""
    echo "[+] $(date +"$tfmt") Start: nix-fast-build '$target'"
    # Do not use ssh ControlMaster as it might cause issues with
    # nix-fast-build the way we use it. SSH multiplexing needs to be disabled
    # both by exporting `NIX_SSHOPTS` and `--remote-ssh-option` since
    # `--remote-ssh-option` only impacts commands nix-fast-build invokes
    # on remote over ssh. However, some nix commands nix-fast-build runs
    # locally (e.g. uploading sources) internally also make use of ssh. Thus,
    # we need to export the relevant option in `NIX_SSHOPTS` to completely
    # disable ssh multiplexing:
    export NIX_SSHOPTS="-o ControlMaster=no"
    # shellcheck disable=SC2086 # intented word splitting of $OPTS
    nix-fast-build \
      --flake "$target" \
      --eval-workers 4 \
      --option accept-flake-config true \
      --remote-ssh-option ControlMaster no \
      --remote-ssh-option StrictHostKeyChecking no \
      --remote-ssh-option UserKnownHostsFile /dev/null \
      --remote-ssh-option ConnectTimeout 10 \
      --no-download --skip-cached \
      --no-nom \
      $OPTS \
      2>&1
    ret="$?"
    echo "[+] $(date +"$tfmt") Done: nix-fast-build '$target' (exit code: $ret)"
    # 'nix_fast_build' is run in its own process. Below, we set the
    # process exit status
    exit $ret
}

################################################################################

main () {
    argparse "$@"
    exit_unless_command_exists nix-fast-build
    exit_unless_command_exists parallel
    [ "$DEBUG" = "true" ] && set -x
    targets_x86=(
        ".#checks"
        ".#nixosConfigurations.az-binary-cache.config.system.build.toplevel"
        ".#nixosConfigurations.az-builder.config.system.build.toplevel"
        ".#nixosConfigurations.az-jenkins-controller.config.system.build.toplevel"
        ".#nixosConfigurations.binarycache.config.system.build.toplevel"
        ".#nixosConfigurations.build3.config.system.build.toplevel"
        ".#nixosConfigurations.build4.config.system.build.toplevel"
        ".#nixosConfigurations.ghaf-coverity.config.system.build.toplevel"
        ".#nixosConfigurations.ghaf-log.config.system.build.toplevel"
        ".#nixosConfigurations.ghaf-proxy.config.system.build.toplevel"
        ".#nixosConfigurations.ghaf-webserver.config.system.build.toplevel"
        ".#nixosConfigurations.himalia.config.system.build.toplevel"
        ".#nixosConfigurations.monitoring.config.system.build.toplevel"
        ".#nixosConfigurations.testagent-dev.config.system.build.toplevel"
        ".#nixosConfigurations.testagent-prod.config.system.build.toplevel"
        ".#nixosConfigurations.testagent-release.config.system.build.toplevel"
    )
    targets_aarch=(
        ".#checks"
        ".#nixosConfigurations.hetzarm.config.system.build.toplevel"
    )
    case "$TARGET" in
        "x86") targets=( "${targets_x86[@]}" ) ;;
        "aarch") targets=( "${targets_aarch[@]}" ) ;;
        *) print_err "TARGET '$TARGET' is not supported" ;;
    esac
    echo "[+] OPTS='$OPTS' TARGET='$TARGET'"
    echo "[+] Running builds, this will take a while..."
    # Don't print out the full 'env_parallel' environment even if DEBUG=true
    set +x
    # Run the function 'nix_fast_build' for each flake target in targets[]
    # array. Each instance of nix_fast_build will run in its own process.
    # We limit the maximum number of concurrent processes to 3 (-j3) and
    # terminate the execution of all jobs immediately if one job fails
    # (--halt-on-error 2).
    env_parallel -j3 --halt-on-error 2 nix_fast_build ::: "${targets[@]}"
}

main "$@"

################################################################################
