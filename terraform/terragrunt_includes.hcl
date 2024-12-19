# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# This file assumes all Terragrunt units live deeper than this file,
# the first level specifying the name of the environment, with possibly more
# levels to distinguish individual units.

locals {
  env_name = split("/", path_relative_to_include())[0]
}


remote_state {
  backend = "azurerm"
  generate = {
    path = "backend.tf"
    if_exists = "overwrite"
  }

  # TODO: manage resources hosting state itself with terragrunt too
  config = {
    # We currently use the same blob container for all state.
    resource_group_name = "ghaf-infra-0-state-eun"
    storage_account_name = "ghafinfra0stateeun"
    container_name = "ghaf-infra-tfstate-container"
    key = "${path_relative_to_include()}.tfstate"
  }
}

inputs  = {
  environment_name = "ghaf-infra-${local.env_name}"
  location = "northeurope"
}

generate "provider" {
  path = "provider.tf"
  if_exists = "overwrite"
  contents = <<EOF
provider "azurerm" {
  # https://github.com/hashicorp/terraform-provider-azurerm/issues/24804
  skip_provider_registration = true
  features {}
}
  EOF
}
