#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

echo "Downloading the following plugins:"
command="jenkinsPlugins2nix"
while IFS= read -r line; do
	echo "> $line"
	command+=" -p $line"
done < <(grep -o '^[^#]*' ./plugins.toml)

eval "$command" >./plugins.nix
