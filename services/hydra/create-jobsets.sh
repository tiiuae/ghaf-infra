#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

# Usage example
# URL=http://localhost:3000 ./create-jobsets.sh

set -euo pipefail

HYDRA_ADMIN_USERNAME=${HYDRA_ADMIN_USERNAME:-admin}
HYDRA_ADMIN_PASSWORD=${HYDRA_ADMIN_PASSWORD:-admin_pass}
URL=${URL:-http://localhost:3000}
PROJECT_NAME=${PROJECT_NAME:-"ghaf"}

mycurl() {
  curl --fail --referer "${URL}" -H "Accept: application/json" -H "Content-Type: application/json" "$@"
}


############################################################
# Login
############################################################

echo "Logging to $URL with user $HYDRA_ADMIN_USERNAME"
cat >data.json <<EOF
{ "username": "$HYDRA_ADMIN_USERNAME", "password": "$HYDRA_ADMIN_PASSWORD" }
EOF
mycurl -X POST -d '@data.json' "$URL/login" -c hydra-cookie.txt


############################################################
# Create project: ghaf
############################################################

# Project properties: 
# https://github.com/NixOS/hydra/blob/c1a5ff3959f8d3d0f13295d29a02084e14dff735/src/lib/Hydra/Controller/Project.pm#L157

echo -e "\nCreating project: $PROJECT_NAME"
cat >data.json <<EOF
{
  "displayname": "Ghaf Framework",
  "description": "Ghaf Framework Description",
  "homepage": "https://github.com/tiiuae/ghaf",
  "enabled": 1,
  "visible": 1
}
EOF
cat data.json
mycurl --silent -X PUT "$URL/project/$PROJECT_NAME" -d @data.json -b hydra-cookie.txt


############################################################
# Create jobset: ghaf-main
############################################################
JOBSET_NAME="ghaf-main"

# Jobset properties:
# https://github.com/NixOS/hydra/blob/c1a5ff3959f8d3d0f13295d29a02084e14dff735/src/lib/Hydra/Controller/Jobset.pm#L272

echo -e "\nCreating jobset: $JOBSET_NAME"
cat >data.json <<EOF
{
  "description": "Ghaf main",
  "type": 1,
  "visible": 1,
  "enabled": 1,
  "checkinterval": 60,
  "schedulingshares": 10,
  "emailoverride": "",
  "keepnr": 2,
  "flake": "github:tiiuae/ghaf/main"
}
EOF
cat data.json
mycurl --silent -X PUT "$URL/jobset/$PROJECT_NAME/$JOBSET_NAME" -d @data.json -b hydra-cookie.txt


############################################################
# Cleanup
############################################################

rm -f data.json hydra-cookie.txt
