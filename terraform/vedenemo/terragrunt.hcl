# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

remote_state {
  backend = "azurerm"
  generate = {
    path = "backend.tf"
    if_exists = "overwrite"
  }

  # TODO: manage state related resources with terragrunt
  # TODO: decide whether we want this per environment or more global 
  config = {
    resource_group_name = "ghaf-infra-0-state-eun"
    storage_account_name = "ghafinfra0stateeun"
    container_name = "ghaf-infra-tfstate-container"
    key = "vedenemo.tfstate"
  }
}

dependency "dns_prod_eun" {
  config_path = "../prod-eun/dns"
}

inputs  = {
  location = "northeurope"
  ns_delegations = {
    "prod-eun" = dependency.dns_prod_eun.outputs.name_servers
  }
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
