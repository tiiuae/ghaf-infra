#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -e # exit immediately if a command fails
set -u # treat unset variables as an error and exit
set -o pipefail # exit if any pipeline command fails

################################################################################

MYNAME=$(basename "$0")
usage () {
    echo "Usage: $MYNAME [activate|destroy|list]"
    echo ""
    echo "This script is a thin wrapper around terraform workspaces to enable private"
    echo "development environment setup for testing Azure infra changes."
    echo ""
    echo "COMMANDS"
    echo "   activate    Activate private infra development environment"
    echo "   destroy     Destroy private infra development environment"
    echo "   list        List current terraform workspaces"
    echo ""
    echo ""
    echo " EXAMPLE:"
    echo "    ./$MYNAME activate"
    echo ""
    echo "    Activate and - unless already created - create a new terraform workspace"
    echo "    to allow testing the infra setup in a private development environment."
    echo ""
    echo ""
    echo " EXAMPLE:"
    echo "    ./$MYNAME destroy"
    echo " "
    echo "    Deactivate and destroy the private development infra that was previously"
    echo "    created with the 'activate' command. This command deletes all the infra"
    echo "    resources."
    echo ""
}

################################################################################

exit_unless_command_exists () {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: command '$1' is not installed" >&2
        exit 1
    fi
}

generate_azure_private_workspace_name () {
    # Generate workspace name based on azure signed-in-user:
    # - .userPrincipalName returns the signed-in azure username
    # - cut removes everything up until the first '@'
    # - sed keeps only letter and number characters
    # - final cut keeps at most 16 characters
    # - tr converts the string to lower case
    # Thus, given a signed-in user 'foo.bar@baz.com', the workspace name
    # becomes 'foobar'.
    # Below command errors out with the azure error message if the azure user
    # is not signed-in.
    WORKSPACE=$(az ad signed-in-user show | jq -cr .userPrincipalName | cut -d'@' -f1 | sed 's/[^a-zA-Z0-9]//g' | cut -c 1-16 | tr '[:upper:]' '[:lower:]')
    # Check WORKSPACE is non-empty and not 'default'
    if [ -z "$WORKSPACE" ] || [ "$WORKSPACE" = "default" ]; then
        echo "Error: invalid workspace name: '$WORKSPACE'"
        exit 1
    fi
}

activate () {
    echo "[+] Activating workspace: '$WORKSPACE'"
    if terraform workspace list | grep -qP "\s$WORKSPACE\$"; then
        terraform workspace select "$WORKSPACE"
    else
        terraform workspace new "$WORKSPACE"
        terraform workspace select "$WORKSPACE"
    fi
    echo "[+] Done, use terraform [validate|plan|apply] to work with your dev infra"
}

destroy () {
    if ! terraform workspace list | grep -qP "\s$WORKSPACE\$"; then
        echo "[+] Devenv workspace '$WORKSPACE' does not exist, nothing to destroy"
        exit 0
    fi
    echo "[+] Destroying workspace: '$WORKSPACE'"
    terraform workspace select "$WORKSPACE"
    terraform apply -destroy -auto-approve
}

list () {
    echo "Terraform workspaces:"
    terraform workspace list
}

################################################################################

main () {
    if [ $# -ne 1 ]; then
       usage
       exit 0
    fi
    if [ "$1" != "activate" ] && [ "$1" != "destroy" ] && [ "$1" != "list" ]; then
        echo "Error: invalid command: '$1'"
        usage
        exit 1
    fi

    exit_unless_command_exists az
    exit_unless_command_exists terraform
    exit_unless_command_exists nix-store
    exit_unless_command_exists jq
    exit_unless_command_exists sed
    exit_unless_command_exists cut
    exit_unless_command_exists tr
    exit_unless_command_exists grep

    # Assigns $WORKSPACE variable
    generate_azure_private_workspace_name

    # It is safe to run terraform init multiple times
    terraform init &> /dev/null

    # Run the given command
    if [ "$1" == "activate" ]; then
        activate
    fi
    if [ "$1" == "destroy" ]; then
        destroy
    fi
    if [ "$1" == "list" ]; then
        list
    fi
}

# Do not execute main() if this script is being sourced
if [ "${0}" = "${BASH_SOURCE[0]}" ]; then
    main "$@"
fi

################################################################################
