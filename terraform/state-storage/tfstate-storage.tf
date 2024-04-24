# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

provider "azurerm" {
  features {}
}

# Variables

variable "location" {
  type        = string
  default     = "northeurope"
  description = "Azure region into which the resources will be deployed"
}

locals {
  # Raise an error if workspace is 'default',
  # this is a workaround to missing asserts in terraform:
  assert_workspace_not_default = regex(
    (terraform.workspace == "default") ?
  "((Force invalid regex pattern)\n\nERROR: workspace 'default' is not allowed" : "", "")

  # Sanitize workspace name:
  # Workspace name defines the state-storage instance
  ws = substr(replace(lower(terraform.workspace), "/[^a-z0-9]/", ""), 0, 16)
}

# Resource group
resource "azurerm_resource_group" "rg" {
  name     = "ghaf-infra-state-${local.ws}"
  location = var.location
}

# Storage container
resource "azurerm_storage_account" "tfstate" {
  # This must be globally unique, max 24 characters
  name                            = "ghafinfrastate${local.ws}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "ghaf-infra-tfstate-container"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}
