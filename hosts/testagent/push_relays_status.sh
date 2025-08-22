#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -e # exit immediately if a command fails
set -u # treat unset variables as an error and exit
set -o pipefail # exit if any pipeline command fails

# This script is parsing kmtronic-status output and push relays statu to prometheus

################################################################################
CONFIG_FILE="/etc/jenkins/test_config.json"
################################################################################
# Arguments
HOSTNAME="${1:-}"
PASSWORD="${2:-}"

if [[ -z "$HOSTNAME" || -z "$PASSWORD" ]]; then
    echo "Usage: $0 <hostname> <password>"
    exit 1
fi

# Extract the relay serial port
relay_serial_port=$(jq -r '.addresses.relay_serial_port' "$CONFIG_FILE")
if [[ -z "$relay_serial_port" || "$relay_serial_port" == "null" ]]; then
  echo "Error: relay_serial_port not found in $CONFIG_FILE" >&2
  exit 1
fi

# Run kmtronic-status to get relay states
mapfile -t lines < <(kmtronic-status "$relay_serial_port")

# Extract each relay status (ON/OFF → 1/0)
# shellcheck disable=SC2034
relay1_status=$([[ $(awk '{print $3}' <<< "${lines[0]}") == "ON" ]] && echo 1 || echo 0)
# shellcheck disable=SC2034
relay2_status=$([[ $(awk '{print $3}' <<< "${lines[1]}") == "ON" ]] && echo 1 || echo 0)
# shellcheck disable=SC2034
relay3_status=$([[ $(awk '{print $3}' <<< "${lines[2]}") == "ON" ]] && echo 1 || echo 0)
# shellcheck disable=SC2034
relay4_status=$([[ $(awk '{print $3}' <<< "${lines[3]}") == "ON" ]] && echo 1 || echo 0)

# Map relay_number → device name
declare -A relay_names
while IFS=: read -r dev_name relay_num; do
    relay_names[$relay_num]="relay-$dev_name"
done < <(
    jq -r '.addresses
           | to_entries[]
           | select(.value | type == "object" and has("relay_number"))
           | "\(.key):\(.value.relay_number)"' "$CONFIG_FILE"
)

# Generate Prometheus metrics output
relay_metrics="# HELP relay_status Relay ON/OFF status\n# TYPE relay_status gauge"
for i in 1 2 3 4; do
    name="${relay_names[$i]:-relay-$i}"
    value_var="relay${i}_status"
    relay_metrics+="\nrelay_status{relay=\"$name\"} ${!value_var}"
done

# Push metrics
push_url="https://monitoring.vedenemo.dev/push/metrics/job/$HOSTNAME-relay"
echo -e "$relay_metrics" | curl -u logger:"$PASSWORD" --data-binary @- "$push_url"
