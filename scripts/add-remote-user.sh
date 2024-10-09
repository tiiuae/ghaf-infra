#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -u # treat unset variables as an error and exit
set -o pipefail # exit if any pipeline command fails

################################################################################

MYNAME=$(basename "$0")
RED='' NONE=''

usage () {
    echo "Usage: $MYNAME [-u USER] -s SSH_OPTS -k PUB_KEY_PATH"
    echo ""
    echo "Add a USER to the remote host using SSH_OPTS for the initial login, adding "
    echo "public key PUB_KEY_PATH to the USER's authorized_keys on the remote host."
    echo ""
    echo "Options:"
    echo " -h    Print this help message"
    echo " -u    Username to be added to the remote host (default=\$USER)"
    echo " -s    SSH options used for the initial login to the remote host"
    echo " -k    Path to the public key that will be added to remote USER's authorized_keys"
    echo " -v    Set the script verbosity to DEBUG"
    echo ""
    echo "Example:"
    echo ""
    echo "  Following command adds user new_user to host remote_host allowing "
    echo "  new_user ssh login to remote_host with key that matches the public "
    echo "  key ~/.ssh/id_new_user.pub. For the initial login, the command uses "
    echo "  admin@remote_host -i admin_key:"
    echo ""
    echo "  $MYNAME -s 'admin@remote_host -i admin_key' -u new_user -k ~/.ssh/id_new_user.pub"
    echo ""
}

################################################################################

print_err () {
    printf "${RED}Error:${NONE} %b\n" "$1" >&2
}

argparse () {
    OPTIND=1; OPT_u=""; OPT_s=""; OPT_k=""; DEBUG="false";
    while getopts "hvu:s:k:" copt; do
        case "${copt}" in
            h)
                usage; exit 0 ;;
            u)
                OPT_u="$OPTARG" ;;
            s)
                OPT_s="$OPTARG" ;;
            k)
                OPT_k="$OPTARG" ;;
            v)
                DEBUG="true" ;;
            *)
                print_err "unrecognized option"; usage; exit 1 ;;
        esac
    done
    shift $((OPTIND-1))
    if [ -n "$*" ]; then
        print_err "unsupported positional argument(s): '$*'"; exit 1
    fi
    if [ -z "$OPT_s" ] || [ -z "$OPT_k" ]; then
        print_err "missing mandatory option(s)"; usage; exit 1
    fi
    if [ -z "$OPT_u" ]; then
        if [ -z "$USER" ]; then
            print_err "'-u USER' not defined and missing environment variable \$USER"
            exit 1;
        fi
        OPT_u="$USER"
    fi
}

exit_unless_file_exists () {
    if ! [ -f "$1" ]; then
        print_err "File not found: \"$1\""
        exit 1
    fi
}

test_remote_sudo () {
    # shellcheck disable=SC2086 # intented word splitting of $OPT_s
    ssh -tt -o ConnectTimeout=5 $OPT_s "sudo -n true || exit 9" >/dev/null
    ret="$?"
    if [ "$ret" = "9" ]; then
        print_err "sudo on remote host requires password"
        exit 1
    elif [ "$ret" != "0" ]; then
        print_err "ssh connection to remote host failed"
        exit 1
    fi
}

# shellcheck disable=SC2086 # intented word splitting of $OPT_s
# shellcheck disable=SC2029 # intented client side expansion of $OPT_u
add_remote_user () {
    if ! ssh $OPT_s "\
        sudo useradd -m -d /home/$OPT_u $OPT_u; \
        sudo grep -q '$OPT_u ALL=(ALL) NOPASSWD: ALL' /etc/sudoers || \
        sudo sh -c \"printf '$OPT_u ALL=(ALL) NOPASSWD: ALL\n' >>/etc/sudoers\"; \
        sudo su - $OPT_u -c 'mkdir -p /home/$OPT_u/.ssh'; \
        sudo su - $OPT_u -c 'touch  /home/$OPT_u/.ssh/authorized_keys'; \
        sudo su - $OPT_u -c 'chmod 700 /home/$OPT_u/.ssh'; \
        sudo su - $OPT_u -c 'chmod 600 /home/$OPT_u/.ssh/authorized_keys'; \
        sudo tee -a /home/$OPT_u/.ssh/authorized_keys; \
        " < "$OPT_k";
    then
        print_err "failed adding user to remote host"
        exit 1
    fi
    if ! ssh $OPT_s "\
        sudo sort -u /home/$OPT_u/.ssh/authorized_keys -o /home/$OPT_u/.ssh/authorized_keys;";
    then
        echo "Warning: failed removing duplicates from remote authorized_keys"
    fi
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
    exit_unless_file_exists "$OPT_k"
    test_remote_sudo
    add_remote_user
    echo ""
    echo "You can now login to remote host as user '$OPT_u' with key '$OPT_k'"
}

main "$@"

################################################################################
