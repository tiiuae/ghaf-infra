#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Runs on the Jenkins controller as the test agent's user, sent over SSH by the
# agent's scheduled deployment drain, and by each agent to disconnect.
# Usage: drain.sh start|idle|end|disconnect <node>...
set -euo pipefail

action=$1
shift
user=$(id -un)
# Ending a drain resumes only the nodes that carry this offline message.
message="Scheduled deployment of $user"
jenkins=http://localhost:8081
cookies=$(mktemp)
trap 'rm -f "$cookies"' EXIT

api() {
  curl -sSf -b "$cookies" -c "$cookies" \
    -H "X-Forwarded-User: $user" -H 'X-Forwarded-Groups: testagents' "$@"
}

# A POST needs a crumb from the same session.
post() {
  local crumb
  crumb=$(api "$jenkins/crumbIssuer/api/json" | sed 's/.*"crumb":"\([^"]*\)".*/\1/')
  api -X POST -H "Jenkins-Crumb: $crumb" "$@"
}

for node in "$@"; do
  status=$(api "$jenkins/computer/$node/api/json?tree=idle,temporarilyOffline,offlineCauseReason")
  case $action in
  start)
    # A node that is already offline for another reason stays as it is.
    if [[ $status != *'"temporarilyOffline":true'* ]]; then
      post --data-urlencode "offlineMessage=$message" "$jenkins/computer/$node/changeOfflineCause"
    fi
    ;;
  idle)
    [[ $status == *'"idle":true'* ]] || exit 1
    ;;
  end)
    if [[ $status == *"$message"* ]]; then
      post "$jenkins/computer/$node/toggleOffline"
    fi
    ;;
  disconnect)
    # Closes a connection the controller still holds, for example from before
    # a reboot. Jenkins rejects a new agent process until the old one is gone.
    post "$jenkins/computer/$node/doDisconnect"
    ;;
  esac
done
