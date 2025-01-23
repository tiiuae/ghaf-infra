#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -e # exit immediately if a command fails
set -u # treat unset variables as an error and exit
set -o pipefail # exit if any pipeline command fails

################################################################################

# This script is a helper to initialize the ghaf terraform infra.

MYDIR=$(dirname "$0")
MYNAME=$(basename "$0")
RED='' NONE=''

################################################################################

usage () {
    echo ""
    echo "Usage: $MYNAME [-h] [-v] [-l LOCATION] [-d] -w WORKSPACE"
    echo ""
    echo "Initialize ghaf-infra workspace with the given name (-w WORKSPACE). This"
    echo "script will not destroy or re-initialize anything if the initialization"
    echo "has already been done earlier."
    echo ""
    echo "Options:"
    echo " -w    Init workspace with the given WORKSPACE name. Name must be 3-16"
    echo "       lowercase characters or numbers i.e. [a-z0-9]{3,16}. Does not"
    echo "       create a new workspace if WORKSPACE already exists in the terraform"
    echo "       remote state, but switches to the existing workspace"
    echo " -l    Azure location name on which the infra will be initialized. See the"
    echo "       Azure location names with command 'az account list-locations -o table'."
    echo "       The default LOCATION is 'northeurope' i.e. '-l northeurope'"
    echo " -v    Set the script verbosity to DEBUG"
    echo " -h    Print this help message"
    echo ""
    echo "Other options:"
    echo " -s    Init state storage"
    echo " -p    Init persistent storage"
    echo " -d    Delete the current workspace"
    echo ""
    echo "Example:"
    echo ""
    echo "  Following command initializes ghaf-infra instance 'myghafinfra'"
    echo "  on the default Azure location (northeurope):"
    echo ""
    echo "  $MYNAME -w myghafinfra"
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
    OUT="/dev/null"; LOCATION="northeurope"; WORKSPACE="";
    OPT_s=""; OPT_p=""; OPT_d="";
    OPTIND=1
    while getopts "hw:l:spvd" copt; do
        case "${copt}" in
            h)
                usage; exit 0 ;;
            v)
                set -x; OUT=/dev/stderr ;;
            l)
                LOCATION="$OPTARG" ;;
            w)
                WORKSPACE="$OPTARG"
                if ! [[ "$WORKSPACE" =~ ^[a-z0-9]{3,16}$ ]]; then
                    print_err "invalid workspace name: '$WORKSPACE'";
                    usage; exit 1
                fi
                ;;
            s)
                OPT_s="true" ;;
            p)
                OPT_p="true" ;;
            d)
                OPT_d="true" ;;
            *)
                print_err "unrecognized option"; usage; exit 1 ;;
        esac
    done
    shift $((OPTIND-1))
    if [ -n "$*" ]; then
        print_err "unsupported positional argument(s): '$*'"; exit 1
    fi
    if [[ -z "$WORKSPACE" && -z "$OPT_s" && -z "$OPT_p" && -z "$OPT_d" ]]; then
        # Intentionally don't promote '-s', '-p', or '-d' usage. They are safe
        # to run but most users of this script should not need to run
        # (or re-run) them
        print_err "missing mandatory option '-w'"
        usage; exit 1
    fi
}

exit_unless_command_exists () {
    if ! command -v "$1" &>"$OUT"; then
        print_err "command '$1' is not installed (Hint: are you inside a nix-shell?)"
        exit 1
    fi
}

azure_location_to_shortloc () {
    # Validate the LOCATION name and map it to SHORTLOC. Canonical source of
    # the short location name information is:
    # https://github.com/claranet/terraform-azurerm-regions/blob/master/regions.tf
    #
    # This script has been tested on following locations, we consider other
    # locations unsupported:
    if [ "$LOCATION" = 'northeurope' ]; then SHORTLOC="eun"
    elif [ "$LOCATION" = 'uaenorth' ]; then SHORTLOC="uaen"
    elif [ "$LOCATION" = 'swedencentral' ]; then SHORTLOC="swec"
    else
        echo "[+] Unsupported location '$LOCATION'"
        exit 1
    fi
}

set_env () {
    # Assign variables STATE_RG, STATE_ACCOUNT and PERSISTENT_RG: these
    # variables are used to select the remote state storage and persistent
    # data used in this ghaf-infra instance.
    STATE_RG="ghaf-infra-0-state-${SHORTLOC}"
    STATE_ACCOUNT="ghafinfra0state${SHORTLOC}"
    PERSISTENT_RG="ghaf-infra-0-persistent-${SHORTLOC}"
    echo "[+] Using state '$STATE_RG'"
    echo "[+] Using persistent '$PERSISTENT_RG'"
    echo "storage_account_rg_name=$STATE_RG" >"$MYDIR/.env"
    echo "storage_account_name=$STATE_ACCOUNT" >>"$MYDIR/.env"
    echo "persistent_rg_name=$PERSISTENT_RG" >>"$MYDIR/.env"
}

init_state_storage () {
    echo "[+] Initializing state storage"
    pushd "$MYDIR/state-storage" >"$OUT"
    terraform init -upgrade >"$OUT"
    terraform workspace select -or-create "$STATE_RG" >"$OUT"
    if az resource list -g "$STATE_RG" &>"$OUT"; then
        echo "[+] State storage is already initialized"
        popd >"$OUT"; return
    fi
    terraform apply -var="location=$LOCATION" -var="account_name=$STATE_ACCOUNT" -auto-approve >"$OUT"
    popd >"$OUT"
}

import_bincache_sigkey () {
    key_name="$1"
    echo "[+] Importing binary cache signing key '$key_name'"
    if terraform state list | grep -q secret_resource.binary_cache_signing_key; then
        echo "[+] Binary cache signing key is already imported"
        return
    fi
    echo "[+] Generating binary cache signing key '$key_name'"
    # https://nix.dev/manual/nix/latest/command-ref/nix-store/generate-binary-cache-key
    nix-store --generate-binary-cache-key "$key_name" sigkey-secret.tmp "sigkey-public-$key_name.tmp"
    var_rg="-var=persistent_resource_group=$PERSISTENT_RG"
    terraform import "$var_rg" secret_resource.binary_cache_signing_key "$(< ./sigkey-secret.tmp)"
    terraform import "$var_rg" secret_resource.binary_cache_signing_key_pub "$(< ./sigkey-public-"$key_name".tmp)"
    terraform apply "$var_rg" -auto-approve >"$OUT"
    rm -f sigkey-secret.tmp
}

run_terraform_init () {
    # Run terraform init declaring the remote state
    opt_state_rg="-backend-config=resource_group_name=$STATE_RG"
    opt_state_acc="-backend-config=storage_account_name=$STATE_ACCOUNT"
    terraform init -upgrade "$opt_state_rg" "$opt_state_acc" >"$OUT"
}

init_persistent_storage () {
    echo "[+] Initializing persistent storage"
    pushd "$MYDIR/persistent" >"$OUT"
    run_terraform_init
    terraform workspace select -or-create "$PERSISTENT_RG" >"$OUT"
    if az resource list -g "$PERSISTENT_RG" &>"$OUT"; then
        echo "[+] Persistent storage is already initialized"
        popd >"$OUT"; return
    fi
    terraform apply -var="location=$LOCATION" -auto-approve >"$OUT"
    popd >"$OUT"
}

init_persistent_resources () {
    echo "[+] Initializing persistent resources"
    pushd "$MYDIR/persistent/resources" >"$OUT"
    run_terraform_init
    for env in "release" "prod" "priv"; do
        ws="$env${SHORTLOC}"
        terraform workspace select -or-create "$ws" >"$OUT"
        import_bincache_sigkey "$env-cache.vedenemo.dev~1"
    done
    popd >"$OUT"
}

init_workspace_persistent () {
    echo "[+] Initializing workspace-specific persistent"
    pushd "$MYDIR/persistent/workspace-specific" >"$OUT"
    if [[ "$WORKSPACE" =~ ^(release|prod|priv)"$SHORTLOC"$ ]]; then
        print_err "workspace name '$WORKSPACE' is taken by persistent resource group"
        exit 1
    fi
    run_terraform_init
    terraform workspace select -or-create "$WORKSPACE" >"$OUT"
    terraform apply -var="persistent_resource_group=$PERSISTENT_RG" -auto-approve >"$OUT"
    popd >"$OUT"
}

init_workspace () {
    echo "[+] Initializing workspace"
    pushd "$MYDIR" >"$OUT"
    run_terraform_init
    terraform workspace select -or-create "$WORKSPACE"
    echo "[+] Listing workspaces:"
    terraform workspace list
    echo "[+] Use 'terraform workspace select <name>' to select a"\
         "workspace, then 'terraform [validate|plan|apply]' to work with the"\
         "given ghaf-infra environment"
    popd >"$OUT"
}

delete_workspace () {
    ws="$(terraform workspace show)"
    echo "[+] Deleting workspace '$ws'"
    pushd "$MYDIR" >"$OUT"
    # This will refuse to destroy 'non-priv' environments: we intentionally
    # don't provide the '-var=convince=true' variable because the workspace
    # specific persistent on 'dev' and 'prod' environments should not be
    # destroyed.
    terraform apply -destroy
    terraform workspace select default
    terraform workspace delete "$ws"
    popd >"$OUT"
    echo "[+] Deleting workspace-specific persistent '$ws'"
    pushd "$MYDIR/persistent/workspace-specific" >"$OUT"
    terraform workspace select "$ws" >"$OUT"
    terraform apply -var="persistent_resource_group=$PERSISTENT_RG" -destroy -auto-approve >"$OUT"
    terraform workspace select default
    terraform workspace delete "$ws"
    popd >"$OUT"
}

################################################################################

main () {
    argparse "$@"
    exit_unless_command_exists az
    exit_unless_command_exists grep
    exit_unless_command_exists nix-store
    exit_unless_command_exists terraform
    azure_location_to_shortloc
    set_env
    if [ -n "$OPT_s" ]; then
        init_state_storage
    fi
    if [ -n "$OPT_p" ]; then
        init_persistent_storage
        init_persistent_resources
    fi
    if [ -n "$OPT_d" ]; then
        delete_workspace
    fi
    if [ -n "$WORKSPACE" ]; then
        init_workspace_persistent
        init_workspace
    fi
}

main "$@"

################################################################################
