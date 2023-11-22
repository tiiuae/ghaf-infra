#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

################################################################################

MYNAME=$(basename "$0")
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

OPTIND=1; OPT_u=""; OPT_s=""; OPT_k=""
while getopts "hu:s:k:" copt; do
    case "${copt}" in
        h)
            usage; exit 0 ;;
        u) 
            OPT_u="$OPTARG" ;;
        s) 
            OPT_s="$OPTARG" ;;
        k) 
            OPT_k="$OPTARG" ;;
        *)
            echo "Error: unrecognized option"; usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))
if [ -n "$*" ]; then
    echo "Error: unsupported positional argument(s): '$*'"; exit 1
fi
if [ -z "$OPT_s" ] || [ -z "$OPT_k" ]; then
    echo "Error: missing mandatory option(s)"; usage; exit 1
fi
if [ -z "$OPT_u" ]; then
    if [ -z "$USER" ]; then
        echo "Error: '-u USER' not defined and missing environment variable \$USER"
        exit 1;
    fi
    OPT_u="$USER"
fi

################################################################################

exit_unless_file_exists () {
    if ! [ -f "$1" ]; then
        echo "Error: File not found: \"$1\""
        exit 1
    fi
}

test_remote_sudo () {
    # shellcheck disable=SC2086 # intented word splitting of $OPT_s
    if ! ssh -o ConnectTimeout=5 $OPT_s "sudo -n true"; then
        echo "Error: ssh connection or sudo on remote host failed"
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
        sudo mkdir -p /home/$OPT_u/.ssh; \
        sudo touch  /home/$OPT_u/.ssh/authorized_keys; \
        sudo chown -R $OPT_u:$OPT_u /home/$OPT_u/.ssh; \
        sudo chmod 700 /home/$OPT_u/.ssh; \
        sudo chmod 600 /home/$OPT_u/.ssh/authorized_keys; \
        sudo tee -a /home/$OPT_u/.ssh/authorized_keys; \
        " < "$OPT_k";
    then
        echo "Error: failed adding user to remote host"
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
    exit_unless_file_exists "$OPT_k"
    test_remote_sudo
    add_remote_user
    echo ""
    echo "You can now login to remote host as user '$OPT_u' with key '$OPT_k'"
}

main "$@"

################################################################################
