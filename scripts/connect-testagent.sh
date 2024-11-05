#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -u          # treat unset variables as an error and exit
set -o pipefail # exit if any pipeline command fails

################################################################################

MYNAME=$(basename "$0")
RED='' NONE=''

usage() {
    echo "Usage: $MYNAME -a AGENT -c CONTROLLER"
    echo ""
    echo "Connect given testagent to given jenkins controller."
    echo "You must have ssh access and passwordless sudo on both."
    echo ""
    echo "Options:"
    echo " -h    Print this help message"
    echo " -a    SSH address of the testagent"
    echo " -c    SSH address of the jenkins controller"
    echo " -v    Set the script verbosity to DEBUG"
    echo ""
    echo "Example:"
    echo ""
    echo "  $MYNAME -a user@testagent-release -c ghaf-jenkins-controller-release.northeurope.cloudapp.azure.com"
    echo ""
}

################################################################################

print_err() {
    printf "${RED}Error:${NONE} %b\n" "$1" >&2
}

argparse() {
    OPTIND=1
    OPT_a=""
    OPT_c=""
    DEBUG="false"
    while getopts "hva:c:" copt; do
        case "${copt}" in
        h)
            usage
            exit 0
            ;;
        a)
            OPT_a="$OPTARG"
            ;;
        c)
            OPT_c="$OPTARG"
            ;;
        v)
            DEBUG="true"
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
    if [ -z "$OPT_a" ] || [ -z "$OPT_c" ]; then
        print_err "missing mandatory option(s)"
        usage
        exit 1
    fi
}

# shellcheck disable=SC2086 # intended word splitting of $OPT_c
get_controller_details() {
    if ! CONTROLLER="$(ssh $OPT_c "cat /var/lib/jenkins-casc/url")"; then
        print_err "Failed reading jenkins controller url!"
        exit 1
    fi
    if ! ADMIN_PASSWORD="$(ssh $OPT_c "sudo cat /var/lib/jenkins/secrets/initialAdminPassword")"; then
        print_err "Failed reading jenkins admin password!"
        exit 1
    fi
}

test_remote_sudo() {
    # shellcheck disable=SC2086 # intented word splitting of $OPT_s
    ssh -tt -o ConnectTimeout=5 $1 "sudo -n true || exit 9" >/dev/null
    ret="$?"
    if [ "$ret" = "9" ]; then
        print_err "sudo on remote host requires password"
        exit 1
    elif [ "$ret" != "0" ]; then
        print_err "ssh connection to remote host failed"
        exit 1
    fi
}

# shellcheck disable=SC2086 # intended word splitting of $OPT_a
# shellcheck disable=SC2029 # intended client side expansion of $CONTROLLER
write_jenkins_env() {
    if ! ssh $OPT_a "\
        sudo bash -c 'echo 'CONTROLLER=$CONTROLLER' > /var/lib/jenkins/jenkins.env'
        sudo bash -c 'echo 'ADMIN_PASSWORD=$ADMIN_PASSWORD' >> /var/lib/jenkins/jenkins.env'
        sudo systemctl restart setup-agents.service
        "; then
        print_err "Failed connecting agent"
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
    if [ "$DEBUG" = "true" ]; then
        set -x
    fi

    test_remote_sudo "$OPT_c"
    test_remote_sudo "$OPT_a"
    get_controller_details
    write_jenkins_env
    echo ""
    echo "Agent is now connected!"
}

main "$@"

################################################################################
