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
  # https://github.com/hashicorp/terraform-provider-azurerm/issues/24804
  skip_provider_registration = true
  features {}
}

# Variables

variable "location" {
  type        = string
  default     = "northeurope"
  description = "Azure region into which the resources will be deployed"
}

variable "account_name" {
  type        = string
  description = "Storage account name must be globally unique, 3-24 lowercase characters"
  default     = ""
  validation {
    condition     = length(var.account_name) > 0
    error_message = "Invalid value"
  }
}

locals {
  # Raise an error if workspace is 'default',
  # this is a workaround to missing asserts in terraform:
  assert_workspace_not_default = regex(
    (terraform.workspace == "default") ?
  "((Force invalid regex pattern)\n\nERROR: workspace 'default' is not allowed" : "", "")
}

# Resource group
resource "azurerm_resource_group" "rg" {
  name     = terraform.workspace
  location = var.location
  lifecycle {
    prevent_destroy = true
  }
}

# Storage container
resource "azurerm_storage_account" "tfstate" {
  # This must be globally unique, max 24 characters
  name                            = var.account_name
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
  lifecycle {
    prevent_destroy = true
  }
}
