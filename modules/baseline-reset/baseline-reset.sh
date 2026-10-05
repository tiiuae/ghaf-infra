#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
umask 077
root_mapper=/dev/mapper/baseline-root
nix_mapper=/dev/mapper/baseline-nix
lower_mount=/.baseline-reset/lower
writable_nix=/.baseline-reset/nix-writable
created_mappers=()

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

# Partition identity survives an interrupted LUKS format.
writable_device() {
  local partuuid=$1 device matches type status=0
  device=/dev/disk/by-partuuid/$partuuid
  [ -b "$device" ] || fail "missing device $device"
  matches=$(blkid -c /dev/null -t "PARTUUID=$partuuid" -o device)
  [ "$(realpath "$device")" = "$matches" ] || fail "ambiguous partition $partuuid on $device"
  type=$(blkid -p --no-part-details -s TYPE -o value "$device") || status=$?
  case "$status:$type" in
  0:crypto_LUKS | 2:) ;;
  *) fail "unexpected contents on $device" ;;
  esac
  realpath "$device"
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

prune_persistent_state() {
  local target
  local -a persistent_files
  read -r -a persistent_files <<<"${BASELINE_PERSISTENT_FILES:?}"

  shopt -s dotglob nullglob
  for target in "$state"/*; do
    prune_persistent_entry "$target" "${target##*/}"
  done
  shopt -u dotglob nullglob
}

prune_persistent_entry() {
  local path=$1 relative=$2 allowed child parent=0
  for allowed in "${persistent_files[@]}"; do
    if [ "$relative" = "$allowed" ]; then
      [ -f "$path" ] && [ ! -L "$path" ] || fail "invalid persistent file: $relative"
      return
    fi
    [[ $allowed != "$relative/"* ]] || parent=1
  done
  if [ "$parent" = 1 ]; then
    [ -d "$path" ] && [ ! -L "$path" ] || fail "invalid persistent directory: $relative"
    for child in "$path"/*; do
      prune_persistent_entry "$child" "$relative/${child##*/}"
    done
  else
    echo "baseline-reset: removing unlisted persistent path: $relative" >&2
    rm -rf --one-file-system -- "$path"
  fi
}

cleanup_mounts() {
  local status=$1 cleanup_status=0 path i
  trap - EXIT
  for path in "$seed/nix" "$fresh_root" "$store" "$root"; do
    if findmnt --mountpoint "$path" >/dev/null 2>&1 && ! umount "$path"; then
      echo "baseline-reset: failed to unmount $path during cleanup" >&2
      cleanup_status=1
    fi
  done
  if ! rm -rf --one-file-system -- "$work"; then
    echo "baseline-reset: failed to remove $work during cleanup" >&2
    cleanup_status=1
  fi
  if [ -n "${keydir:-}" ] && ! rm -rf -- "$keydir"; then
    echo "baseline-reset: failed to remove initrd keys during cleanup" >&2
    cleanup_status=1
  fi
  if [ "$status" -ne 0 ] || [ "$cleanup_status" -ne 0 ]; then
    for ((i = ${#created_mappers[@]} - 1; i >= 0; i--)); do
      if ! cryptsetup close "${created_mappers[i]}"; then
        echo "baseline-reset: failed to close ${created_mappers[i]} during cleanup" >&2
        cleanup_status=1
      fi
    done
  fi
  [ "$status" -ne 0 ] && exit "$status"
  exit "$cleanup_status"
}

mount_top_levels() {
  if [ -e /etc/initrd-release ]; then
    udevadm settle --timeout=30 || fail "device discovery did not finish"
  fi
  root_uuid=$(device_uuid "${BASELINE_ROOT:?}" btrfs)
  nix_uuid=$(device_uuid "${BASELINE_NIX:?}" btrfs)
  boot_uuid=$(device_uuid "${BASELINE_BOOT:?}" vfat)
  root_writable=$(writable_device "${BASELINE_ROOT_WRITABLE_PARTUUID:?}")
  if [ -n "${BASELINE_NIX_WRITABLE_PARTUUID:-}" ]; then
    nix_writable=$(writable_device "$BASELINE_NIX_WRITABLE_PARTUUID")
  fi
  work=$(mktemp -d /run/baseline-reset.XXXXXXXX)
  root=$work/root
  store=$work/store
  seed=$work/seed
  fresh_root=$work/fresh-root
  mkdir "$root" "$store" "$seed" "$fresh_root"
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

check_mapper_mount() {
  local path=$1 mapper=$2 raw=$3 source field value backing=
  [ "$(findmnt -nro FSTYPE --mountpoint "$path")" = btrfs ] || fail "wrong filesystem at $path"
  source=$(findmnt -nro SOURCE --mountpoint "$path")
  source=${source%%\[*}
  [ "$(realpath "$source")" = "$(realpath "$mapper")" ] || fail "wrong mapper mounted at $path"
  while read -r field value _; do
    [ "$field" != device: ] || backing=$value
  done < <(cryptsetup status "${mapper##*/}")
  [ -n "$backing" ] && [ "$(realpath "$backing")" = "$raw" ] || fail "wrong device behind $mapper"
}

format_writable() {
  local raw=$1 name=$2 key=$keydir/$2.key
  head -c 64 /dev/random >"$key"
  cryptsetup luksFormat --batch-mode --type luks2 \
    --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file "$key" "$raw"
  cryptsetup open --type luks --key-file "$key" "$raw" "$name"
  created_mappers+=("$name")
  rm -f -- "$key"
  mkfs.btrfs -f "/dev/mapper/$name" >/dev/null
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
  local action=$2 snapshot incoming expected actual id system_path opts
  case "$action" in
  check | dry-activate | test) exit 0 ;;
  boot | switch) ;;
  *) fail "unsupported activation action: $action" ;;
  esac

  system_path=$(realpath "$1") || fail "missing system $1"
  parse_system "$system_path"
  [ -e "$system/init" ] || fail "system has no init: $system"
  mount_top_levels
  check_mapper_mount / "$root_mapper" "$root_writable"
  check_mount "$lower_mount" "$nix_uuid" btrfs @lower
  [[ ,$(findmnt -nro OPTIONS --mountpoint "$lower_mount"), == *,ro,* ]] || fail "lower mount is writable"
  check_mount /var/lib/baseline-reset "$root_uuid" btrfs @persist
  [ "$(findmnt -nro UUID --mountpoint /boot)" = "$boot_uuid" ] || fail "wrong filesystem mounted at /boot"
  [ "$(findmnt -nro FSTYPE --mountpoint /boot)" = vfat ] || fail "wrong filesystem type at /boot"
  if [ -n "${nix_writable:-}" ]; then
    check_mapper_mount "$writable_nix" "$nix_mapper" "$nix_writable"
  else
    install -d -m 755 "$writable_nix"
    [ "$(findmnt -nro TARGET -T "$writable_nix")" = / ] || fail "Nix writable path is outside root"
  fi
  if findmnt --mountpoint /nix >/dev/null 2>&1; then
    [ "$(findmnt -nro FSTYPE --mountpoint /nix)" = overlay ] || fail "wrong filesystem at /nix"
    [ "$(btrfs property get "$store/@lower" ro)" = ro=true ] || fail "lower snapshot is writable"
    opts=$(findmnt -nro OPTIONS --mountpoint /nix)
    opts=${opts//\/sysroot/}
    [[ ,$opts, == *,lowerdir=$lower_mount,* ]] || fail "wrong overlay lower directory"
    [[ ,$opts, == *,upperdir=$writable_nix/upper,* ]] || fail "wrong overlay upper directory"
    [[ ,$opts, == *,workdir=$writable_nix/work,* ]] || fail "wrong overlay work directory"
  else
    [ "$(findmnt -nro TARGET -T /nix)" = / ] || fail "installer /nix is outside encrypted root"
    [ "$(btrfs property get "$store/@lower" ro)" = ro=false ] || fail "missing running /nix overlay"
  fi

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
  cryptsetup status baseline-root >/dev/null 2>&1 && fail "root mapper is already open"
  if [ -n "${nix_writable:-}" ]; then
    cryptsetup status baseline-nix >/dev/null 2>&1 && fail "Nix mapper is already open"
  fi

  prune_persistent_state

  remove_subvolume "$store/@lower"
  btrfs subvolume snapshot -r "$snapshot" "$store/@lower" >/dev/null
  btrfs filesystem sync "$store" >/dev/null
  keydir=$(mktemp -d /baseline-reset-keys.XXXXXXXX)
  format_writable "$root_writable" baseline-root
  if [ -n "${nix_writable:-}" ]; then
    format_writable "$nix_writable" baseline-nix
  fi

  mount -t btrfs "$root_mapper" "$fresh_root"
  install -d -m 755 "$fresh_root/etc" "$fresh_root/nix" "$fresh_root/.baseline-reset/lower" \
    "$fresh_root/.baseline-reset/nix-writable" "$fresh_root/var/lib/baseline-reset"
  install -m 444 "$state/machine-id" "$fresh_root/etc/machine-id"
  sync -f "$fresh_root"
  umount "$fresh_root"
  [ "$(btrfs property get "$store/@lower" ro)" = ro=true ] || fail "lower snapshot is not read-only"
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
