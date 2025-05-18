#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

################################################################################

# This script is a helper to run nix-fast-build for specified flake targets.
# The main benefit this script provides over using nix-fast-build directly,
# is the target selector filter ('-f').

# TODO: we should file a PR to implement the '--filter' option directly in
# nix-fast-build. Also, '-s' in this wrapper is a workaround to an issue
# that should be fixed in nix-fast-build: see more details in function
# 'symlink_results' in this file.

################################################################################

# Set shell options after env_parallel as it would otherwise fail
set -e # exit immediately if a command fails
set -E # exit immediately if a command fails (subshells)
set -u # treat unset variables as an error and exit
set -o pipefail # exit if any pipeline command fails

TMPDIR="$(mktemp -d --suffix .tmpbuild)"
MYNAME=$(basename "$0")

################################################################################

usage () {
    echo ""
    echo "Usage: $MYNAME [-h] [-v] [-s SYMLINK] [-o OPTS] {-f FILTER | -t 'TARGET1 [TARGET2 ...]'}"
    echo ""
    echo "Helper script to run nix-fast-build for specified flake targets."
    echo ""
    echo "Options:"
    echo " -h    Print this help message."
    echo " -v    Set the script verbosity to DEBUG."
    echo " -s    Symlink top-level outputs with the out-link SYMLINK."
    echo " -o    Options passed directly to nix-fast-build. See available options at:"
    echo "       https://github.com/Mic92/nix-fast-build#reference."
    echo " -f    Target selector filter - regular expression applied over flake outputs"
    echo "       to determine the build targets. This option is mutually exclusive with"
    echo "       option -t."
    echo "       Example: -f '^devShells\.'"
    echo " -t    Target selector list - space separated list of flake outputs to build. "
    echo "       This options is mutually exclusive with option -f. "
    echo "       Example: -t 'devShells.x86_64-linux.default checks.x86_64-linux.treefmt'"
    echo ""
    echo ""
    echo "Examples:"
    echo ""
    echo "  --"
    echo ""
    echo "  Following command builds the target 'checks.x86_64-linux.treefmt' locally:"
    echo ""
    echo "    $MYNAME -t checks.x86_64-linux.treefmt"
    echo ""
    echo "  --"
    echo ""
    echo "  Following command builds the target 'checks.x86_64-linux.treefmt' on the"
    echo "  remote builder 'my_builder' authenticating as current user, symlinking"
    echo "  build outputs in current directory with 'result-' prefix:"
    echo ""
    echo "    $MYNAME -t checks.x86_64-linux.treefmt -o '--remote my-builder' -s result-"
    echo ""
    echo "  --"
    echo ""
    echo "  Following command builds all 'checks.x86_64-linux.*debug' targets on"
    echo "  the specified remote builder 'my_builder' authenticating as user 'me'"
    echo "  with ssh key '~/.ssh/my_key', not downloading build results from remote, "
    echo "  skipping builds that are already in binary cache, and accepting the target "
    echo "  flake configuration (assuming 'me' is a nix trusted user on remote):"
    echo ""
    echo "    $MYNAME \\"
    echo "      -f '^checks\.x86_64-linux\..*debug$' \\"
    echo "      -o '--remote me@my_builder \\"
    echo "          --remote-ssh-option IdentityFile ~/.ssh/my_key \\"
    echo "          --no-download --skip-cached \\"
    echo "          --option accept-flake-config true"
    echo ""
    echo "  --"
    echo ""
    echo "  Following command builds all non-release aarch64 checks targets"
    echo "  (outputs 'checks.aarch64-linux.' not followed by a word 'release'"
    echo "  in the output target name) on the specified remote builder 'my_builder'"
    echo "  authenticating as user 'me':"
    echo ""
    echo "    $MYNAME \\"
    echo "      -f '^checks\.aarch64-linux\.((?!release).)*$' \\"
    echo "      -o '--remote me@my_builder"
    echo ""
}

################################################################################

print_err () {
    printf "${RED}Error:${NONE} %b\n" "$1" >&2
}

on_exit () {
    echo "[+] Removing tmpdir: '$TMPDIR'"
    rm -fr "$TMPDIR"
}

parallel () {
    # Gnu parallel in nixos-unstable does not work correctly for our use-case,
    # therefore, using the version from 24.11. TODO: file a bug in nixpkgs.
    nix run nixpkgs/nixos-24.11#parallel -- "$@"
}

nix-fast-build () {
    # nix-fast-build in nixos-unstable does not work correctly for our use-case,
    # therefore, using the version from 24.11. TODO: file a bug in nix-fast-build.
    nix run nixpkgs/nixos-24.11#nix-fast-build -- "$@"
}

jq () {
    nix run --inputs-from .# nixpkgs#jq -- "$@"
}

filter_targets () {
    filter="$1"
    typeset -n ref_TARGETS=$2 # argument $2 is passed as reference
    # Output all flake output names
    nix flake show --all-systems --json |\
      jq  '[paths(scalars) as $path | { ($path|join(".")): getpath($path) }] | add' \
      >"$TMPDIR/all"
    # Remove leading spaces and quotes, keep only '.name' attributes:
    sed -n -E "s/^.*\"(\S*).name\".*$/\1/p" "$TMPDIR/all" > "$TMPDIR/out_targets"
    # Remove leading spaces and quotes, keep only 'nixos-configuration' types:
    # append '.config.system.build.toplevel' which represents the complete
    # system closure of the given NixOS configuration as package:
    sed -n -E \
      "s/^.*\"(\S*).type\": \"nixos-configuration\".*$/\1.config.system.build.toplevel/p" \
      "$TMPDIR/all" >> "$TMPDIR/out_targets"
    # Apply the 'filter' argument
    if ! grep -P "${filter}" "$TMPDIR/out_targets" | sort | uniq >"$TMPDIR/out_filtered";
    then
        print_err "No flake outputs match filter: '$filter'"; exit 1
    fi
    # Read lines from $TMPDIR/out_filtered to array 'ref_TARGETS' which
    # is passed as reference, so this changes the caller's variable
    # shellcheck disable=SC2034 # ref_TARGETS is not unused
    readarray -t ref_TARGETS<"$TMPDIR/out_filtered"
}

argparse () {
    # Parse arguments
    OPTS=""; SYMLINK=""; FILTER=""; TARGETS=();
    OPTIND=1
    while getopts "hvs:o:f:t:" copt; do
        case "${copt}" in
            h)
                usage; exit 0 ;;
            v)
                set -x ;;
            o)
                OPTS="$OPTARG" ;;
            s)
                SYMLINK="$OPTARG" ;;
            f)
                FILTER="$OPTARG" ;;
            t)
                TARGETS+=("$OPTARG") ;;
            *)
                print_err "unrecognized option"; usage; exit 1 ;;
        esac
    done
    shift $((OPTIND-1))
    if [ -n "$*" ]; then
        print_err "unsupported positional argument(s): '$*'"; exit 1
    fi
    if [ -z "$FILTER" ] && (( ${#TARGETS[@]} == 0 )); then
        print_err "either '-f' or '-t' must be specified"; usage; exit 1;
    fi
    if [ -n "$FILTER" ] && (( ${#TARGETS[@]} != 0 )); then
        print_err "'-f' and '-t' are mutually exclusive"; exit 1;
    fi
    if [ -n "$SYMLINK" ] && grep -q -- '--no-download' <<<"$OPTS"; then
        print_err "'-s' with '--no-download': would likely miss some out-links"; exit 1;
    fi
    echo "[+] OPTS='$OPTS'"
    if [ -n "$FILTER" ]; then
        echo "[+] FILTER='$FILTER'"
        filter_targets "$FILTER" TARGETS
    fi
    if (( ${#TARGETS[@]} != 0 )); then
        echo "[+] TARGETS:"
        printf '  %s\n' "${TARGETS[@]}"
    fi
}

fast_build () {
    set -ueEo pipefail
    target="$1"
    logfile="$TMPDIR/nix-fast-build-out.$target.$PPID.log"
    timer_begin=$(date +%s)
    echo "[+] $(date +"%H:%M:%S") Start: nix-fast-build '$target'"
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
      --flake ".#$target" \
      --eval-workers 4 \
      --remote-ssh-option ControlMaster no \
      --remote-ssh-option ConnectTimeout 10 \
      --no-nom \
      $OPTS \
      2>&1 | tee -a "$logfile"
    ret="$?"
    lapse=$(( $(date +%s) - timer_begin ))
    echo "[+] $(date +"%H:%M:%S") Stop: nix-fast-build '$target' (took ${lapse}s; exit $ret)"
    # nix-fast-build doesn't create out-links locally when building on remote.
    # TODO: this should be fixed in nix-fast-build instead the below hack.
    if [ -n "$SYMLINK" ] && grep -q -- '--remote' <<<"$OPTS"; then
        echo "[+] Symlinking build outputs"
        matches=$(grep -c -E '^/nix/store/[^ ]+$' "$logfile")
        i=0; while IFS= read -r path; do
            if ! [ -e "$path" ]; then
                echo "[+] Skipping symlink (not available locally): $path"
                continue
            fi
            ((i=i+1))
            link_name="${SYMLINK}${target}"
            if (( matches > 1 )); then
              link_name="${SYMLINK}${target}_$i"
            fi
            echo "[+] Creating symlink: $link_name -> $path"
            ln -sfn "$path" "$link_name"
        done < <(grep -E '^/nix/store/[^ ]+$' "$logfile")
    fi
    # This function runs in its own process; set the process exit status:
    exit $ret
}

################################################################################

main () {
    # Colorize output if stdout is to a terminal (and not to pipe or file)
    RED='' NONE=''
    if [ -t 1 ]; then RED='\033[1;31m'; NONE='\033[0m'; fi
    # Parse arguments
    argparse "$@"
    # Remove TMPDIR on exit
    trap on_exit EXIT
    echo "[+] Using tmpdir: '$TMPDIR'"
    # Build TARGETS with nix-fast-build
    echo "[+] Running builds ..."
    # Run the function 'fast_build' for each flake target in TARGETS[]
    # array. Each instance of fast_build will run in its own process.
    # We limit the maximum number of concurrent processes with -j and
    # terminate the execution of all jobs immediately if one job fails
    # (--halt 2). Keep-order (-k) and line-buffer (--lb) keep the output
    # logs readable.
    export -f fast_build nix-fast-build; export OPTS TMPDIR SYMLINK;
    parallel --will-cite -j 4 --halt 2 -k --lb fast_build ::: "${TARGETS[@]}"
}

main "$@"

################################################################################
