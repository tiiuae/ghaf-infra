#!/usr/bin/env bash
# shellcheck disable=SC2181,SC2059

# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -u # treat unset variables as an error and exit

# This script is a helper to test the ghaf terraform infra deployment

################################################################################

MYNAME=$(basename "$0")
RED='' GREEN='' WHITE='' NONE=''

################################################################################

usage () {
    echo "Usage: $MYNAME [-h] [-v] [-l LOCATION] [-p PUBKEY] -w WORKSPACE"
    echo ""
    echo "Perform basic end-to-end testing for ghaf-infra deployment."
    echo "The target deployment is determined based on WORKSPACE and"
    echo "LOCATION arguments."
    echo ""
    echo "This script assumes the user running this script can access "
    echo "the target jenkins-controller and binary-cache VMs over ssh."
    echo ""
    echo "Options:"
    echo " -h    Print this help message"
    echo " -v    Set the script verbosity to DEBUG"
    echo " -l    Azure location name (default: -l northeurope)"
    echo " -p    Nix public key (default: determined based on WORKSPACE and LOCATION)"
    echo " -w    Target terraform workspace name"
    echo ""
    echo "Example:"
    echo ""
    echo "  Following command runs basic end-to-end testing for the"
    echo "  ghaf-infra instance deployed in workspace 'myghafinfra'"
    echo "  in the default LOCATION (northeurope):"
    echo ""
    echo "  $MYNAME -w myghafinfra"
    echo ""
}

################################################################################

print_err () {
    printf "${RED}Error:${NONE} %b\n" "$1" >&2
}

print_success () {
    printf "${GREEN}SUCCESS${NONE}\n" >&2
}

print_skip () {
    printf "${WHITE}SKIPPED${NONE}\n" >&2
}

print_info () {
    printf "${WHITE}\nMore info:\n${NONE}%b\n" "$1" >&2
}

print_running () {
    printf "%-60b" "  $1 ... " >&2
}

argparse () {
    LOCATION="northeurope"; PUBKEY=""; WORKSPACE=""; OPTIND=1
    while getopts "hvl:p:w:" copt; do
        case "${copt}" in
            h)
                usage; exit 0 ;;
            v)
                set -x ;;
            l)
                LOCATION="$OPTARG" ;;
            w)
                WORKSPACE="$OPTARG" ;;
            p)
                PUBKEY="$OPTARG" ;;
            *)
                print_err "unrecognized option"; usage; exit 1 ;;
        esac
    done
    shift $((OPTIND-1))
    if [ -n "$*" ]; then
        print_err "unsupported positional argument(s): '$*'"; exit 1
    fi
    if [ -z "$WORKSPACE" ]; then
        print_err "missing mandatory option (-w)"; usage; exit 1
    fi
    if [ -z "$PUBKEY" ]; then
        if [ "$LOCATION" != "northeurope" ]; then
            print_err "nix public key not known, manually specify it with -p PUBKEY"; exit 1
        fi
        case "$WORKSPACE" in
            dev*) PUBKEY="prod-cache.vedenemo.dev~1:JcytRNMJJdYJVQCYwLNsrfVhct5dhCK2D3fa6O1WHOI=" ;;
            prod*) PUBKEY="prod-cache.vedenemo.dev~1:JcytRNMJJdYJVQCYwLNsrfVhct5dhCK2D3fa6O1WHOI=" ;;
            release*) PUBKEY="release-cache.vedenemo.dev~1:kxSUdZvNF8ax7hpJMu+PexEBQGUkZDqeugu+pwz/ACk=" ;;
            *) PUBKEY="priv-cache.vedenemo.dev~1:FmJGfAkx+2fhqpzHGT/V3M35VcPm2pfkCuiTo8xQD0A=" ;;
        esac
    fi
}

exit_unless_command_exists () {
    if ! command -v "$1" &>/dev/null; then
        print_err "command '$1' is not installed (Hint: are you inside a nix-shell?)"
        exit 1
    fi
}

exec_ssh_cmd () {
    cmd="$1"
    host="$2"
    vararg="${3:-none}"
    ssh_args="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    # shellcheck disable=SC2029,SC2086
    ret=$(ssh $ssh_args "$host" "$cmd" 2>&1)
    if [ $? -ne 0 ]; then
        if [ "$vararg" = "silent_err" ]; then
            return 2
        fi
        print_err "'$cmd' on host '$host' failed"
        print_info "$ret"
        exit 1
    fi
    if [ "$vararg" = "echo_out" ]; then
        echo "$ret"
    fi
}

################################################################################

test_dns_lookup () {
    host="$1"
    info="$2"
    print_running "${FUNCNAME[0]} ($info)"
    if ! host "$host" >/dev/null; then
        print_err "DNS lookup for '$host' failed"
        exit 1
    fi
    print_success
}

test_jenkins_controller_ssh_connection () {
    host="$1"
    print_running "${FUNCNAME[0]}"
    exec_ssh_cmd "whoami" "$host"
    print_success
}

test_jenkins_controller_services () {
    host="$1"
    print_running "${FUNCNAME[0]}"
    check_systemd_service "$host" "cloud-init"
    check_systemd_service "$host" "jenkins"
    check_systemd_service "$host" "caddy"
    print_success
}

test_binary_cache_services () {
    host="$1"
    print_running "${FUNCNAME[0]}"
    # Skip this test if there's no ssh access to the binary cache
    exec_ssh_cmd "whoami" "$host" "silent_err"
    if [ $? -eq 2 ]; then
        print_skip
        return 0
    fi
    check_systemd_service "$host" "cloud-init"
    check_systemd_service "$host" "caddy"
    print_success
}

test_binary_cache_url () {
    host="$1"
    print_running "${FUNCNAME[0]}"
    endpoint="https://$host/nix-cache-info"
    if ! curl -Ls "$endpoint" >/dev/null; then
        print_err "URL is not accessible: '$endpoint'"
        exit 1
    fi
    print_success
}

test_build_end_to_end () {
    controller="$1"
    bincache="$2"
    arch="$3"
    print_running "${FUNCNAME[0]} ($arch)"
    # Trigger a build on jenkins-controller, returning the build output hash
    hash=$(trigger_build "$controller" "$arch")
    if [ -z "$hash" ]; then exit 1; fi
    # Request narinfo given the build hash we just generated
    narinfo=$(get_narinfo "$bincache" "$hash")
    if [ -z "$narinfo" ]; then exit 1; fi
    # Find the keyname from the narinfo
    keyname=$(echo "$narinfo" | sed -n -E 's|Sig: ([^:]+).*|\1|p')
    if [ -z "$keyname" ]; then
        print_err "failed reading nix keyname from narinfo"
        print_info "narinfo:\n$narinfo"
        exit 1
    fi
    # Verify the binary is signed with the expected public nix signing key
    store="https://$bincache/"
    storepath="/nix/store/$hash-example"
    ret=$(nix store verify --store "$store" "$storepath" --trusted-public-keys "$PUBKEY" 2>&1)
    if [ $? -ne 0 ]; then
        print_err "build result '$storepath' is not signed with '$PUBKEY'"
        print_info "nix store verify returned:\n$ret" >&2
        exit 1
    fi
    print_success
}

check_systemd_service () {
    host="$1"
    service="$2"
    # Wait until the service is no longer activating or at most 60 seconds
    cmd="TIMER=0; while (( TIMER < 60 )); do ((TIMER++)); sudo systemctl status $service | grep 'Active: activating' && sleep 1 || break; done"
    exec_ssh_cmd "$cmd" "$host"
    # Query service status
    cmd="sudo systemctl status $service"
    exec_ssh_cmd "$cmd" "$host"
}

trigger_build () {
    controller="$1"
    arch="$2"
    cmd="nix-build --system $arch --expr '(import <nixpkgs> {}).writeText \"example\" (builtins.toString builtins.currentTime)'"
    hash=$(exec_ssh_cmd "$cmd" "$controller" "echo_out" | sed -n -E 's|.*/nix/store/([0-9a-z]{32})-example$|\1|p' | head -n1)
    if [ -z "$hash" ]; then
        print_err "failed reading the build output hash"
        exit 1
    fi
    echo "$hash"
}

get_narinfo () {
    bincache="$1"
    hash="$2"
    endpoint="https://$bincache/$hash.narinfo"
    narinfo=$(curl -Ls "$endpoint")
    if [ $? -ne 0 ] || [ -z "$narinfo" ] ; then
        print_err "failed reading narinfo: '$endpoint'"
        exit 1
    fi
    echo "$narinfo"
}

run_tests () {
    controller="ghaf-jenkins-controller-$WORKSPACE.$LOCATION.cloudapp.azure.com"
    bincache="ghaf-binary-cache-$WORKSPACE.$LOCATION.cloudapp.azure.com"

    test_dns_lookup "$controller" "controller"
    test_dns_lookup "$bincache" "bincache"
    test_jenkins_controller_ssh_connection "$controller"
    test_jenkins_controller_services "$controller"
    test_binary_cache_services "$bincache"
    test_binary_cache_url "$bincache"
    test_build_end_to_end "$controller" "$bincache" "x86_64-linux"
    test_build_end_to_end "$controller" "$bincache" "aarch64-linux"
}

################################################################################

main () {
    # Colorize output if stdout is to a terminal (and not to pipe or file)
    if [ -t 1 ]; then
      RED='\033[1;31m'
      GREEN='\033[1;32m'
      WHITE='\033[1;37m'
      NONE='\033[0m'
    fi
    argparse "$@"
    exit_unless_command_exists nix
    exit_unless_command_exists ssh
    exit_unless_command_exists host
    exit_unless_command_exists sed
    run_tests
}

main "$@"

################################################################################
