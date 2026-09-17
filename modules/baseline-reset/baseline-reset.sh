#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
umask 077

fail() {
  echo "baseline-reset: $*" >&2
  exit 1
}

# Probe without blkid's cache so cloned filesystems are rejected too.
device_uuid() {
  local device=$1 type=$2 id matches
  [ -b "$device" ] || fail "missing device $device"
  [ "$(blkid -p -s TYPE -o value "$device")" = "$type" ] || fail "wrong filesystem on $device"
  id=$(blkid -p -s UUID -o value "$device")
  matches=$(blkid -c /dev/null -t "UUID=$id" -o device)
  [ "$(realpath "$device")" = "$matches" ] || fail "ambiguous filesystem $id on $device"
  printf '%s\n' "$id"
}

remove_subvolume() {
  [ ! -e "$1" ] || btrfs subvolume delete --recursive --commit-after "$1" >/dev/null
}

parse_system() {
  local path=$1
  [[ $path =~ ^/nix/store/([0-9a-z]{32})-nixos-system-[^/[:space:]]+$ ]] || fail "not a raw NixOS system: $path"
  system_hash=${BASH_REMATCH[1]}
  system=$path
}

valid_machine_id() {
  local id
  [ -f "$1" ] || return 1
  id=$(cat "$1")
  [[ $id =~ ^[0-9a-f]{32}$ ]] && [ "$id" != 00000000000000000000000000000000 ]
}

cleanup_mounts() {
  local status=$1 cleanup_status=0 path
  trap - EXIT
  for path in "$seed/nix" "$store" "$root"; do
    if findmnt --mountpoint "$path" >/dev/null 2>&1 && ! umount "$path"; then
      echo "baseline-reset: failed to unmount $path during cleanup" >&2
      cleanup_status=1
    fi
  done
  if ! rm -rf --one-file-system -- "$work"; then
    echo "baseline-reset: failed to remove $work during cleanup" >&2
    cleanup_status=1
  fi
  [ "$status" -ne 0 ] && exit "$status"
  exit "$cleanup_status"
}

mount_top_levels() {
  root_uuid=$(device_uuid "${BASELINE_ROOT:?}" btrfs)
  nix_uuid=$(device_uuid "${BASELINE_NIX:?}" btrfs)
  boot_uuid=$(device_uuid "${BASELINE_BOOT:?}" vfat)
  work=$(mktemp -d /run/baseline-reset.XXXXXXXX)
  root=$work/root
  store=$work/store
  seed=$work/seed
  mkdir "$root" "$store" "$seed"
  trap 'cleanup_mounts "$?"' EXIT
  mount -t btrfs -o subvolid=5 "$BASELINE_ROOT" "$root"
  mount -t btrfs -o subvolid=5 "$BASELINE_NIX" "$store"
  state=$root/@persist
  btrfs subvolume show "$state" >/dev/null || fail "provision @persist before enabling baseline reset"
}

check_mount() {
  local path=$1 id=$2 type=$3 subvolume=$4
  [ "$(findmnt -nro UUID --mountpoint "$path")" = "$id" ] || fail "wrong filesystem mounted at $path"
  [ "$(findmnt -nro FSTYPE --mountpoint "$path")" = "$type" ] || fail "wrong filesystem type at $path"
  [ "$(findmnt -nro FSROOT --mountpoint "$path")" = "/$subvolume" ] || fail "wrong subvolume mounted at $path"
}

keep_system() {
  local init path name hash
  init=$(realpath "$1/init" 2>/dev/null) || return 0
  path=${init%/init}
  [[ $path =~ ^/nix/store/[0-9a-z]{32}-nixos-system-[^/[:space:]]+$ ]] || return 0
  name=${path#/nix/store/}
  hash=${name%%-*}
  keep[$hash]=1
}

retain_baselines() {
  local path name
  declare -A keep=()
  keep_system /run/booted-system
  keep_system "$system"
  for path in /nix/var/nix/profiles/system-*-link; do
    keep_system "$path"
  done
  for path in "$store"/@baseline-*; do
    [ -e "$path" ] || continue
    name=${path##*/@baseline-}
    [[ $name =~ ^[0-9a-z]{32}$ ]] || continue
    [ -n "${keep[$name]:-}" ] || remove_subvolume "$path"
  done
  btrfs filesystem sync "$store" >/dev/null
}

save_baseline() {
  local action=$2 snapshot incoming expected actual id system_path
  case "$action" in
  check | dry-activate | test) exit 0 ;;
  boot | switch) ;;
  *) fail "unsupported activation action: $action" ;;
  esac

  system_path=$(realpath "$1") || fail "missing system $1"
  parse_system "$system_path"
  [ -e "$system/init" ] || fail "system has no init: $system"
  mount_top_levels
  check_mount / "$root_uuid" btrfs @root
  check_mount /nix "$nix_uuid" btrfs @nix
  check_mount /var/lib/baseline-reset "$root_uuid" btrfs @persist
  [ "$(findmnt -nro UUID --mountpoint /boot)" = "$boot_uuid" ] || fail "wrong filesystem mounted at /boot"
  [ "$(findmnt -nro FSTYPE --mountpoint /boot)" = vfat ] || fail "wrong filesystem type at /boot"

  if [ "$BASELINE_SSH" = 1 ]; then
    [ -s "$state/ssh/ssh_host_ed25519_key" ] || fail "missing SSH host identity"
  fi
  if valid_machine_id "$state/machine-id"; then
    id=$(cat "$state/machine-id")
  elif valid_machine_id /etc/machine-id; then
    id=$(cat /etc/machine-id)
  else
    id=$(cat /proc/sys/kernel/random/uuid)
    id=${id//-/}
  fi
  if ! valid_machine_id "$state/machine-id"; then
    printf '%s\n' "$id" >"$state/machine-id.new"
    sync "$state/machine-id.new"
    mv -T "$state/machine-id.new" "$state/machine-id"
    sync -f "$state"
  fi

  incoming=$store/@baseline-incoming
  snapshot=$store/@baseline-$system_hash
  remove_subvolume "$incoming"
  if [ -e "$snapshot" ]; then
    [ "$(btrfs property get "$snapshot" ro)" = ro=true ] || fail "baseline is not read-only: $system"
    [ "$(readlink "$snapshot/var/nix/profiles/system-1-link")" = "$system" ] || fail "baseline names another system"
    retain_baselines
    exit 0
  fi

  btrfs subvolume create "$incoming" >/dev/null
  chmod 755 "$incoming"
  mkdir "$seed/nix"
  mount -t btrfs -o subvol=@baseline-incoming "$BASELINE_NIX" "$seed/nix"
  umask 022
  nix copy --no-check-sigs --from local --to "local?root=$seed" "$system"
  mkdir -p "$seed/nix/var/nix/profiles" "$seed/nix/var/nix/gcroots"
  ln -s "$system" "$seed/nix/var/nix/profiles/system-1-link"
  ln -s system-1-link "$seed/nix/var/nix/profiles/system"
  ln -s "$system" "$seed/nix/var/nix/gcroots/baseline-reset"
  expected=$work/expected
  actual=$work/actual
  nix path-info --recursive "$system" | LC_ALL=C sort >"$expected"
  nix path-info --store "local?root=$seed" --all | LC_ALL=C sort >"$actual"
  cmp "$expected" "$actual" || fail "baseline registrations do not match the system closure"
  sync -f "$seed/nix"
  umount "$seed/nix"
  btrfs property set "$incoming" ro true
  btrfs filesystem sync "$store" >/dev/null
  mv -T "$incoming" "$snapshot"
  btrfs filesystem sync "$store" >/dev/null
  retain_baselines
}

restore_baseline() {
  local arg count=0 snapshot snapshot_system
  local -a cmdline
  [ -e /etc/initrd-release ] || fail "reset must run in the initrd"
  findmnt --mountpoint /sysroot >/dev/null && fail "system root is already mounted"
  read -r -a cmdline </proc/cmdline
  for arg in "${cmdline[@]}"; do
    case "$arg" in
    init=*)
      count=$((count + 1))
      init=${arg#init=}
      ;;
    esac
  done
  [ "$count" = 1 ] && [[ $init == /nix/store/*/init ]] || fail "kernel command line must name exactly one raw system init"
  parse_system "${init%/init}"
  mount_top_levels
  snapshot=$store/@baseline-$system_hash
  [ "$(btrfs property get "$snapshot" ro)" = ro=true ] || fail "missing read-only baseline for $system"
  snapshot_system=$snapshot/store/${system#/nix/store/}
  [ -d "$snapshot_system" ] && [ -e "$snapshot_system/init" ] || fail "baseline is missing the booted system"
  [ "$(readlink "$snapshot/var/nix/profiles/system")" = system-1-link ] || fail "invalid baseline system profile"
  [ "$(readlink "$snapshot/var/nix/profiles/system-1-link")" = "$system" ] || fail "baseline names another system"
  valid_machine_id "$state/machine-id" || fail "missing persistent machine ID"
  if [ "$BASELINE_SSH" = 1 ]; then
    [ -s "$state/ssh/ssh_host_ed25519_key" ] || fail "missing SSH host identity"
  fi

  remove_subvolume "$root/@root"
  btrfs subvolume create "$root/@root" >/dev/null
  chmod 755 "$root/@root"
  mkdir -m 755 "$root/@root/etc"
  install -m 444 "$state/machine-id" "$root/@root/etc/machine-id"
  remove_subvolume "$store/@nix"
  btrfs subvolume snapshot "$snapshot" "$store/@nix" >/dev/null
  btrfs filesystem sync "$root" >/dev/null
  btrfs filesystem sync "$store" >/dev/null
  btrfs subvolume show "$root/@root" >/dev/null
  btrfs subvolume show "$store/@nix" >/dev/null
}

case "${1:-}" in
save)
  [ "$#" = 3 ] || fail "usage: baseline-reset save SYSTEM ACTION"
  save_baseline "$2" "$3"
  ;;
initrd)
  [ "$#" = 1 ] || fail "usage: baseline-reset initrd"
  restore_baseline
  ;;
*) fail "internal command required" ;;
esac
