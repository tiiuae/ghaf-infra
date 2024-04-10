#!/bin/bash
set -e

URL=${URL:-"https://ghaf-binary-cache-dev.northeurope.cloudapp.azure.com/nix-cache-info"}

function check_cache() {
    output=$(curl -Ls "$URL")
    if [ "$output" != "StoreDir: /nix/store" ]; then
        echo "NixOS binary cache is not available or changed."
        exit 1
    fi
}

function extract_hash() {
    if [ ! -z "$1" ]; then
        hash=$1
    else
        full_path=$(ls -la result | awk '{print $NF}')
        hash=${full_path##*/}
        hash=${hash%-nixos-disk-image}
    fi

    if [[ ! "$hash" ]]; then
        echo "Failed to extract hash."
        exit 1
    fi

    echo $hash
}

function get_narinfo() {
    narinfo_url="https://ghaf-binary-cache-dev.northeurope.cloudapp.azure.com/$1.narinfo"
    curl_output=$(curl -L "$narinfo_url" -s | grep -v "References")

    if [[ ! "$curl_output" ]]; then
        echo "Failed to retrieve or process narinfo."
        exit 1
    fi

    echo "$curl_output" | grep "URL:" | awk '{print $2}'
}

function download_nar() {
    nar_url="https://ghaf-binary-cache-dev.northeurope.cloudapp.azure.com/$1"
    curl -L "$nar_url" -o nixos.img.nar.zst
}

function decompress_nar() {
    zstd --decompress nixos.img.nar.zst -o nixos.img.nar
}

function restore_nar() {
    cat nixos.img.nar | nix-store --restore imagedir
}

check_cache
hash=$(extract_hash "$1")
nar_file_name=$(get_narinfo "$hash")
download_nar "$nar_file_name"
decompress_nar
restore_nar
ls -la imagedir