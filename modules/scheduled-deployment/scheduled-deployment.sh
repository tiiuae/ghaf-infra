#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
umask 077

state=/var/lib/scheduled-deployment
metrics_dir=/run/ghaf-deployment-metrics
drain=/run/current-system/etc/scheduled-deployment/drain
exec 9>"$state/run.lock"
flock 9
target=

publish() {
  install -m 0644 "$state/scheduled.prom" "$metrics_dir/.scheduled.prom.tmp"
  mv -f "$metrics_dir/.scheduled.prom.tmp" "$metrics_dir/scheduled.prom"
}

# Record the result of this run. The metrics are kept in the state directory,
# because the textfile directory in /run is emptied on reboot.
finish() {
  echo "$1: $2 (target: ${target:-none})"
  if [[ $1 == deployed || $1 == up_to_date ]]; then
    touch "$state/succeeded"
  fi
  {
    echo '# TYPE ghaf_scheduled_deployment_result_timestamp_seconds gauge'
    echo "ghaf_scheduled_deployment_result_timestamp_seconds{result=\"$1\",reason=\"$2\",target=\"$target\"} $(date +%s)"
    echo '# TYPE ghaf_scheduled_deployment_last_success_timestamp_seconds gauge'
    echo "ghaf_scheduled_deployment_last_success_timestamp_seconds $(stat -c %Y "$state/succeeded" 2>/dev/null || echo 0)"
    echo '# TYPE ghaf_scheduled_deployment_rejected_info gauge'
    grep -xE '[0-9a-f]{40}' "$state/rejected" 2>/dev/null | sort -u |
      sed 's/.*/ghaf_scheduled_deployment_rejected_info{revision="&"} 1/' || true
  } >"$state/scheduled.prom"
  publish
  exit 0
}

# Administrators can edit or delete /var/lib/scheduled-deployment/rejected to retry.
reject_target() {
  echo "$target" >>"$state/rejected"
  rm "$state/pending"
  finish failed "$1"
}

# Post-deploy checks of the running system. Errors are explicit, because errexit
# does not apply in a condition.
verify() {
  local revision failed_units
  revision=$(/run/current-system/sw/bin/nixos-version --configuration-revision) || return 1
  if [[ $revision != "$target" ]]; then
    echo "Running revision $revision is not $target"
    return 1
  fi
  failed_units=$(systemctl --failed --no-legend --plain) || return 1
  if [[ -n $failed_units ]]; then
    echo "Failed units: $failed_units"
    return 1
  fi
  timeout 300 /run/current-system/etc/scheduled-deployment/checks
}

# A drain lasts until the target is verified, so a failed deployment leaves the
# host drained.
end_drain() {
  if [[ -x $drain ]] && ! "$drain" end; then
    finish failed drain_not_ended
  fi
}

# The pending file is written before an activation, and removed once the target
# is verified or rejected. A boot activation leaves it for verification after the
# reboot; one left in the same boot was interrupted or failed to roll back.
boot_id=$(cat /proc/sys/kernel/random/boot_id)
pending_boot_id=
if [[ -f $state/pending ]]; then
  read -r target pending_boot_id <"$state/pending"
fi

if [[ $1 == verify ]]; then
  if [[ -f $state/pending && $pending_boot_id != "$boot_id" ]]; then
    echo "Verifying booted target $target; a failure is left for an administrator"
    if ! verify; then
      reject_target post_boot_checks
    fi
    rm "$state/pending"
    end_drain
    finish deployed reboot_verified
  fi
  if [[ -f $state/scheduled.prom ]]; then
    publish
  fi
  exit 0
fi

if [[ -f $state/hold ]]; then
  echo "Operator hold: $(<"$state/hold")"
  finish held operator_hold
fi
# Deploy at most once per window. A failed attempt leaves the window open, so a
# fix or revert merged during the window is picked up.
if (($(date +%s) - $(stat -c %Y "$state/succeeded" 2>/dev/null || echo 0) < 86400)); then
  echo 'Deployed or up to date within the last 24 hours'
  exit 0
fi
if [[ -f $state/pending ]]; then
  if [[ $pending_boot_id == "$boot_id" ]]; then
    echo "Activation of $target was interrupted or not rolled back; check the host, then remove $state/pending"
    finish failed unverified_activation
  fi
  finish held boot_verification_pending
fi

# Ignore machine and user Git credentials, and never prompt for credentials.
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0
repo=$state/repository.git
if [[ ! -d $repo ]]; then
  git init --bare -b main "$repo"
  git -C "$repo" config remote.origin.promisor true
  git -C "$repo" config remote.origin.partialclonefilter tree:0
fi
git -C "$repo" config remote.origin.url "$DEPLOY_REPOSITORY"
if ! git -C "$repo" fetch --filter=tree:0 --no-tags origin +refs/heads/main:refs/heads/main; then
  finish skipped network_error
fi
target=$(git -C "$repo" rev-parse refs/heads/main)
echo "Pinned main at $target"

previous=$(readlink -e /run/current-system)
staged_system=$(readlink -e /nix/var/nix/profiles/system)
running=$("$previous/sw/bin/nixos-version" --configuration-revision)
staged=$("$staged_system/sw/bin/nixos-version" --configuration-revision)
if [[ ! $running =~ ^[0-9a-f]{40}$ ]] || ! git -C "$repo" merge-base --is-ancestor "$running" "$target"; then
  finish held running_branch
fi
if [[ $staged != "$running" && $staged != "$target" ]]; then
  finish held staged_branch
fi
if grep -Fxq "$target" "$state/rejected" 2>/dev/null; then
  finish skipped rejected_target
fi
if [[ $running == "$target" ]]; then
  finish up_to_date already_running
fi
# Require 10 GiB free on the filesystem where build outputs are stored.
if (($(df -B1 --output=avail /nix/store | tail -1) < 10 * 1024 ** 3)); then
  finish skipped low_disk_space
fi

echo "Building $DEPLOY_HOST at $target"
if ! nix build --option accept-flake-config false --option access-tokens '' \
  --builders '' \
  --out-link "$state/result" \
  "git+$DEPLOY_REPOSITORY?ref=main&rev=$target#nixosConfigurations.\"$DEPLOY_HOST\".config.system.build.toplevel"; then
  # Nix also fails this way when inputs or caches are unavailable; retry in the window.
  finish skipped build_failed
fi
new=$(readlink -e "$state/result")
if [[ ! -x $new/etc/scheduled-deployment/checks ]]; then
  # Activation would stop the removed unit that runs it.
  echo 'Target disables scheduled deployment; deploy this revision manually'
  finish held module_disabled
fi

# Until activation starts, every exit ends the drain.
if [[ -x $drain ]]; then
  trap end_drain EXIT
  echo 'Draining'
  if ! "$drain" start; then
    finish skipped drain_failed
  fi
  drain_started=$(date +%s)
  until "$drain" idle; do
    if [[ -f $state/hold ]]; then
      finish held operator_hold
    fi
    if (($(date +%s) - drain_started > 3600)); then
      finish skipped drain_timeout
    fi
    sleep 30
  done
fi

# The hold command takes this lock: a hold set from here on waits until this run ends.
exec 8>"$state/activation.lock"
flock 8
if [[ -f $state/hold ]]; then
  finish held operator_hold
fi
# A manual deployment during the build must not be overwritten.
if [[ $(readlink -e /run/current-system) != "$previous" ||
$(readlink -e /nix/var/nix/profiles/system) != "$staged_system" ]]; then
  finish held configuration_changed
fi
failed_units=$(systemctl --failed --no-legend --plain)
if [[ -n $failed_units ]]; then
  echo "Failed units: $failed_units"
  finish skipped failed_units
fi

action=switch
if [[ $(readlink -e /run/booted-system/{kernel,initrd,kernel-modules}) != "$(readlink -e "$new"/{kernel,initrd,kernel-modules})" ]]; then
  echo 'Booted kernel, initrd or kernel modules differ; activating at boot'
  action=boot
elif ! "$new/bin/switch-to-configuration" check; then
  echo 'Pre-switch checks, such as switch inhibitors, refuse a switch; activating at boot'
  action=boot
fi

echo "Activating $target with $action"
trap - EXIT
echo "$target $boot_id" >"$state/pending"
reason=activation_failed
if nix-env --profile /nix/var/nix/profiles/system --set "$new" &&
  "$new/bin/switch-to-configuration" "$action"; then
  if [[ $action == boot ]]; then
    echo 'Rebooting; the target is verified after boot'
    systemctl reboot
    exit 0
  fi
  reason=post_switch_checks
  if verify; then
    rm "$state/pending"
    end_drain
    finish deployed switch_verified
  fi
fi
echo "Restoring $previous with $action"
if ! nix-env --profile /nix/var/nix/profiles/system --set "$previous" ||
  ! "$previous/bin/switch-to-configuration" "$action"; then
  # The pending file stays, so later runs report the host as failed.
  finish failed rollback_failed
fi
reject_target "$reason"
