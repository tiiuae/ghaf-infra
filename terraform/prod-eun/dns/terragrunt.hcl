# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

include "root" {
  path = find_in_parent_folders("terragrunt_includes.hcl")
}

dependency "rg" {
  config_path = "../rg"
}

inputs = {
  resource_group_name = dependency.rg.outputs.resource_group_name
}
