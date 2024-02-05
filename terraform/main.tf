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
    key                  = "ghaf-infra.tfstate"
  }
}

################################################################################

# Current signed-in user
data "azurerm_client_config" "current" {}

# Variables
variable "location" {
  type        = string
  default     = "northeurope"
  description = "Azure region into which the resources will be deployed"
}

# Use azure_region module to get the short name of the Azure region,
# see: https://registry.terraform.io/modules/claranet/regions/azurerm/latest 
module "azure_region" {
  source       = "claranet/regions/azurerm"
  azure_region = var.location
}

locals {
  # Raise an error if workspace is 'default',
  # this is a workaround to missing asserts in terraform:
  assert_workspace_not_default = regex(
    (terraform.workspace == "default") ?
  "((Force invalid regex pattern)\n\nERROR: workspace 'default' is not allowed" : "", "")

  # Short name of the Azure region, see:
  # https://github.com/claranet/terraform-azurerm-regions/blob/master/REGIONS.md
  shortloc = module.azure_region.location_short

  # Sanitize workspace name
  ws = substr(replace(lower(terraform.workspace), "/[^a-z0-9]/", ""), 0, 16)

  # Environment-specific configuration options.
  # See Azure vm sizes and specs at:
  # https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux
  # E.g. 'Standard_D1_v2' means: 1 vCPU, 3.5 GiB RAM
  opts = {
    priv = {
      vm_size_binarycache = "Standard_D1_v2"
      vm_size_builder     = "Standard_D2_v3"
      vm_size_controller  = "Standard_D2_v3"
      num_builders        = 1
    }
    dev = {
      vm_size_binarycache = "Standard_D1_v2"
      vm_size_builder     = "Standard_D4_v3"
      vm_size_controller  = "Standard_D4_v3"
      num_builders        = 1
    }
    prod = {
      vm_size_binarycache = "Standard_D2_v3"
      vm_size_builder     = "Standard_D8_v3"
      vm_size_controller  = "Standard_D8_v3"
      num_builders        = 2
    }
  }

  # Read ssh-keys.yaml into local.ssh_keys
  ssh_keys = yamldecode(file("../ssh-keys.yaml"))

  # Map workspace name to configuration name:
  #  !"dev" && !"prod" ==> "priv"
  #  "dev"             ==> "dev"
  #  "prod"            ==> "prod"
  # This determines the configuration options used in the
  # ghaf-infra instance (defines e.g. vm_sizes and number of builders)
  # TODO: allow overwriting this with an input variable
  conf = local.ws != "dev" && local.ws != "prod" ? "priv" : local.ws

  # env is used to identify workspace-specific resources:
  env = local.ws

  # Selects the persistent data used in the ghaf-infra instance, currently
  # either "dev" or "prod"
  # (see ./persistent)
  persistent_data = local.conf == "priv" ? "dev" : local.conf
}

################################################################################

# Resource group for this ghaf-infra instance
resource "azurerm_resource_group" "infra" {
  name     = "ghaf-infra-${local.env}"
  location = var.location
}

################################################################################

# Virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "ghaf-infra-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.infra.location
  resource_group_name = azurerm_resource_group.infra.name
}

# Slice out a subnet for jenkins
resource "azurerm_subnet" "jenkins" {
  name                 = "ghaf-infra-jenkins"
  resource_group_name  = azurerm_resource_group.infra.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Slice out a subnet for the buidlers
resource "azurerm_subnet" "builders" {
  name                 = "ghaf-infra-builders"
  resource_group_name  = azurerm_resource_group.infra.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.4.0/28"]
}

################################################################################

# Storage account and storage container used to store VM images

resource "azurerm_storage_account" "vm_images" {
  name                            = "img${local.env}${local.shortloc}"
  resource_group_name             = azurerm_resource_group.infra.name
  location                        = azurerm_resource_group.infra.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
}

resource "azurerm_storage_container" "vm_images" {
  name                  = "ghaf-infra-vm-images"
  storage_account_name  = azurerm_storage_account.vm_images.name
  container_access_type = "private"
}

################################################################################

# Data sources to access 'persistent' data, see ./persistent

data "azurerm_storage_account" "binary_cache" {
  name                = "ghafbincache${local.persistent_data}${local.shortloc}"
  resource_group_name = "ghaf-infra-persistent-${local.shortloc}"
}
data "azurerm_storage_container" "binary_cache_1" {
  name                 = "binary-cache-v1"
  storage_account_name = data.azurerm_storage_account.binary_cache.name
}

data "azurerm_key_vault" "ssh_remote_build" {
  name                = "ssh-builder-${local.persistent_data}-${local.shortloc}"
  resource_group_name = "ghaf-infra-persistent-${local.shortloc}"
  provider            = azurerm
}

data "azurerm_key_vault_secret" "ssh_remote_build" {
  name         = "remote-build-ssh-private-key"
  key_vault_id = data.azurerm_key_vault.ssh_remote_build.id
  provider     = azurerm
}

data "azurerm_key_vault_secret" "ssh_remote_build_pub" {
  name         = "remote-build-ssh-public-key"
  key_vault_id = data.azurerm_key_vault.ssh_remote_build.id
  provider     = azurerm
}

data "azurerm_key_vault" "binary_cache_signing_key" {
  name                = "bche-sigkey-${local.persistent_data}-${local.shortloc}"
  resource_group_name = "ghaf-infra-persistent-${local.shortloc}"
  provider            = azurerm
}

data "azurerm_key_vault_secret" "binary_cache_signing_key" {
  name         = "binary-cache-signing-key-priv"
  key_vault_id = data.azurerm_key_vault.binary_cache_signing_key.id
  provider     = azurerm
}

################################################################################
