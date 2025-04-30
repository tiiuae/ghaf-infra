#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd "$SCRIPT_DIR"/../ || exit 1
OUTDIR="$(pwd)"/hosts/azure/jenkins-controller
JENKINS_VERSION=$(nix eval --raw --impure --expr 'let flake = builtins.getFlake ("git+file://" + toString ./.); in (import flake.inputs.nixpkgs {system = "x86_64-linux";}).jenkins.version')
python "$SCRIPT_DIR"/resolve_plugins.py --jenkins-version "$JENKINS_VERSION" --output "$OUTDIR"/plugins.json
