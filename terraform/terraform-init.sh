#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2024 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

set -e # exit immediately if a command fails
set -u # treat unset variables as an error and exit
set -o pipefail # exit if any pipeline command fails

################################################################################

# This script is a helper to initialize the ghaf terraform infra:
# - init terraform state storage
# - init persistent secrets such as binary cache signing key (per environment)
# - init persistent binary cache storage (per environment)
#
# This script will not do anything if the initialization has already been done.
# In other words, it's safe to run this script many times. It will not destroy
# or re-initialize anything if the initialization has already taken place. 

################################################################################

MYDIR=$(dirname "$0")

################################################################################

exit_unless_command_exists () {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: command '$1' is not installed" >&2
        exit 1
    fi
}

init_state_storage () {
    echo "[+] Initializing state storage"
    # See: ./state-storage 
    pushd "$MYDIR/state-storage" >/dev/null
    terraform init >/dev/null
    if ! terraform apply -auto-approve &>/dev/null; then
        echo "[+] State storage is already initialized"
    fi
    popd >/dev/null
}

import_bincache_sigkey () {
    env="$1"
    echo "[+] Importing binary cache signing key '$env'"
    # Skip import if signing key is imported already
    if terraform state list | grep -q secret_resource.binary_cache_signing_key_"$env"; then
        echo "[+] Binary cache signing key is already imported"
        return
    fi
    # Generate and import the key
    nix-store --generate-binary-cache-key "ghaf-infra-$env" sigkey-secret.tmp "sigkey-public-$env.tmp"
    terraform import secret_resource.binary_cache_signing_key_"$env" "$(< ./sigkey-secret.tmp)"
    rm -f sigkey-secret.tmp
}

init_persistent () {
    echo "[+] Initializing persistent data"
    # See: ./persistent
    pushd "$MYDIR/persistent" >/dev/null
    terraform init > /dev/null
    # Default persistent instance: 'eun' (northeurope)
    terraform workspace select eun &>/dev/null || terraform workspace new eun
    import_bincache_sigkey "prod"
    import_bincache_sigkey "dev"
    echo "[+] Applying possible changes"
    terraform apply -auto-approve >/dev/null
    popd >/dev/null
}

init_terraform () {
    echo "[+] Running terraform init"
    terraform -chdir="$MYDIR" init >/dev/null
}

################################################################################

main () {

    exit_unless_command_exists az
    exit_unless_command_exists terraform
    exit_unless_command_exists nix-store
    exit_unless_command_exists grep

    init_state_storage
    init_persistent
    init_terraform

}

main "$@"

################################################################################
