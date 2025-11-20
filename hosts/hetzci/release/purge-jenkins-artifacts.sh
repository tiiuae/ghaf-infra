#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -eEuo pipefail

# Find anything exactly two paths deep from the artifacts directory, i.e.:
# /var/lib/jenkins/artifacts/*/*/. If the matching path directly contains
# only broken symlinks or directories, the path is removed.
while IFS= read -r path; do
  if find "$path" -maxdepth 1 -mindepth 1 -not -xtype l -not -type d | read -r; then
    continue
  fi
  echo "Removing: '$path'"
  rm -fr "$path"
done < <(find /var/lib/jenkins/artifacts -maxdepth 2 -mindepth 2)
