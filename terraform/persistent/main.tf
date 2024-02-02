# SPDX-FileCopyrightText: 2024 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

provider "azurerm" {
  features {}
}

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    secret = {
      source = "numtide/secret"
    }
  }
}

################################################################################

terraform {
  # Backend for storing terraform state (see ../state-storage)
  backend "azurerm" {
    resource_group_name  = "ghaf-infra-state"
    storage_account_name = "ghafinfratfstatestorage"
    container_name       = "ghaf-infra-tfstate-container"
    key                  = "ghaf-infra-persistent.tfstate"
  }
}

################################################################################

# Variables
variable "location" {
  type        = string
  default     = "northeurope"
  description = "Azure region into which the resources will be deployed"
}

# Use azure_region module to get the short name of the Azure region,
# see: https://registry.terraform.io/modules/claranet/regions/azurerm/latest 
# and: https://github.com/claranet/terraform-azurerm-regions/blob/master/REGIONS.md
module "azure_region" {
  source       = "claranet/regions/azurerm"
  azure_region = var.location
}

locals {
  shortloc = module.azure_region.location_short
}

# Resource group
resource "azurerm_resource_group" "persistent" {
  name     = "ghaf-infra-persistent"
  location = var.location
}

# Current signed-in user
data "azurerm_client_config" "current" {}

################################################################################

# Resources

# secret_resouce must be created on import, e.g.:
#
#   nix-store --generate-binary-cache-key foo secret-key public-key
#   terraform import secret_resource.binary_cache_signing_key_dev "$(< ./secret-key)"
#   terraform apply
#
# Ghaf-infra automates the creation in 'init-ghaf-infra.sh'
resource "secret_resource" "binary_cache_signing_key_dev" {
  lifecycle {
    prevent_destroy = true
  }
}
resource "secret_resource" "binary_cache_signing_key_prod" {
  lifecycle {
    prevent_destroy = true
  }
}

module "builder_ssh_key_prod" {
  source = "./builder-ssh-key"
  # Must be globally unique
  builder_ssh_keyvault_name = "ssh-builder-prod-${local.shortloc}"
  resource_group_name       = azurerm_resource_group.persistent.name
  location                  = azurerm_resource_group.persistent.location
  tenant_id                 = data.azurerm_client_config.current.tenant_id
}

module "builder_ssh_key_dev" {
  source = "./builder-ssh-key"
  # Must be globally unique
  builder_ssh_keyvault_name = "ssh-builder-dev-${local.shortloc}"
  resource_group_name       = azurerm_resource_group.persistent.name
  location                  = azurerm_resource_group.persistent.location
  tenant_id                 = data.azurerm_client_config.current.tenant_id
}

module "binary_cache_sigkey_prod" {
  source = "./binary-cache-sigkey"
  # Must be globally unique
  bincache_keyvault_name = "bche-sigkey-prod-${local.shortloc}"
  secret_resource        = secret_resource.binary_cache_signing_key_prod
  resource_group_name    = azurerm_resource_group.persistent.name
  location               = azurerm_resource_group.persistent.location
  tenant_id              = data.azurerm_client_config.current.tenant_id
}

module "binary_cache_sigkey_dev" {
  source = "./binary-cache-sigkey"
  # Must be globally unique
  bincache_keyvault_name = "bche-sigkey-dev-${local.shortloc}"
  secret_resource        = secret_resource.binary_cache_signing_key_dev
  resource_group_name    = azurerm_resource_group.persistent.name
  location               = azurerm_resource_group.persistent.location
  tenant_id              = data.azurerm_client_config.current.tenant_id
}

module "binary_cache_storage_prod" {
  source = "./binary-cache-storage"
  # Must be globally unique
  bincache_storage_account_name = "ghafbincacheprod${local.shortloc}"
  resource_group_name           = azurerm_resource_group.persistent.name
  location                      = azurerm_resource_group.persistent.location
}

module "binary_cache_storage_dev" {
  source = "./binary-cache-storage"
  # Must be globally unique
  bincache_storage_account_name = "ghafbincachedev${local.shortloc}"
  resource_group_name           = azurerm_resource_group.persistent.name
  location                      = azurerm_resource_group.persistent.location
}

################################################################################
