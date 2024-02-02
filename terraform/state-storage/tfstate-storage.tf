# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
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

# Resource group

resource "azurerm_resource_group" "rg" {
  name     = "ghaf-infra-state"
  location = "northeurope"
}

# Storage container

resource "azurerm_storage_account" "tfstate" {
  # This must be globally unique, max 24 characters
  name                            = "ghafinfratfstatestorage"
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
