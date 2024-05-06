# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
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
    # resource_group_name and storage_account_name are set by the callee
    # from command line in terraform init, see terraform-init.sh
    container_name = "ghaf-infra-tfstate-container"
    key            = "ghaf-infra.tfstate"
  }
}

################################################################################

# Current signed-in user
data "azurerm_client_config" "current" {}

variable "envtype" {
  type        = string
  description = "Set the environment type; determines e.g. the Azure VM sizes"
  default     = "priv"
  validation {
    condition     = contains(["priv", "dev", "prod"], var.envtype)
    error_message = "Must be either \"priv\", \"dev\", or \"prod\""
  }
}

variable "envfile" {
  type        = string
  description = "Error out if .env-file is missing"
  default     = ".env"
  validation {
    condition     = fileexists(var.envfile)
    error_message = "ERROR: missing .env-file: (re-)run terraform-init.sh to initialize your environment"
  }
}

# Use azure_region module to get the short name of the Azure region,
# see: https://registry.terraform.io/modules/claranet/regions/azurerm/latest
module "azure_region" {
  source       = "claranet/regions/azurerm"
  azure_region = data.azurerm_storage_account.tfstate.location
}

locals {
  # Raise an error if workspace is 'default',
  # this is a workaround to missing asserts in terraform:
  assert_workspace_not_default = regex(
    (terraform.workspace == "default") ?
  "((Force invalid regex pattern)\n\nERROR: workspace 'default' is not allowed" : "", "")

  envs = { for tuple in regexall("(.*)=(.*)", file(var.envfile)) : tuple[0] => tuple[1] }

  # Short name of the Azure region, see:
  # https://github.com/claranet/terraform-azurerm-regions/blob/master/REGIONS.md
  shortloc = module.azure_region.location_short

  assert_region_mismatch_1 = regex(
    ("${local.shortloc}" != "eun" && local.envs["storage_account_rg_name"] != "ghaf-infra-state-${local.shortloc}") ?
  "((Force invalid regex pattern)\n\nERROR: region (non-eun) mismatch, re-run terraform-init.sh" : "", "")

  assert_region_mismatch_2 = regex(
    ("${local.shortloc}" == "eun" && local.envs["storage_account_rg_name"] != "ghaf-infra-state") ?
  "((Force invalid regex pattern)\n\nERROR: region (eun) mismatch, re-run terraform-init.sh" : "", "")

  # Sanitize workspace name
  ws = substr(replace(lower(terraform.workspace), "/[^a-z0-9]/", ""), 0, 16)

  # Environment-specific configuration options.
  # See Azure vm sizes and specs at:
  # https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux
  # E.g. 'Standard_D2_v3' means: 2 vCPU, 8 GiB RAM
  opts = {
    priv = {
      vm_size_binarycache     = "Standard_D2_v3"
      osdisk_size_binarycache = "50"
      vm_size_builder_x86     = "Standard_D2_v3"
      vm_size_builder_aarch64 = "Standard_D2ps_v5"
      osdisk_size_builder     = "150"
      vm_size_controller      = "Standard_E2_v5"
      osdisk_size_controller  = "150"
      num_builders_x86        = 1
      num_builders_aarch64    = 1
      # 'priv' and 'dev' environments use the same binary cache signing key
      binary_cache_public_key = "ghaf-infra-dev:EdgcUJsErufZitluMOYmoJDMQE+HFyveI/D270Cr84I="
      binary_cache_url        = "https://ghaf-binary-cache-${local.ws}.${azurerm_resource_group.infra.location}.cloudapp.azure.com"
    }
    dev = {
      vm_size_binarycache     = "Standard_D2_v3"
      osdisk_size_binarycache = "250"
      vm_size_builder_x86     = "Standard_D4_v3"
      vm_size_builder_aarch64 = "Standard_D4ps_v5"
      osdisk_size_builder     = "250"
      vm_size_controller      = "Standard_E4_v5"
      osdisk_size_controller  = "500"
      num_builders_x86        = 1
      num_builders_aarch64    = 1
      # 'priv' and 'dev' environments use the same binary cache signing key
      binary_cache_public_key = "ghaf-infra-dev:EdgcUJsErufZitluMOYmoJDMQE+HFyveI/D270Cr84I="
      binary_cache_url        = "https://ghaf-binary-cache-${local.ws}.${azurerm_resource_group.infra.location}.cloudapp.azure.com"
    }
    prod = {
      vm_size_binarycache     = "Standard_D2_v3"
      osdisk_size_binarycache = "250"
      vm_size_builder_x86     = "Standard_D8_v3"
      vm_size_builder_aarch64 = "Standard_D8ps_v5"
      osdisk_size_builder     = "500"
      vm_size_controller      = "Standard_E4_v5"
      osdisk_size_controller  = "1000"
      num_builders_x86        = 2
      num_builders_aarch64    = 2
      binary_cache_public_key = "ghaf-infra-prod:DIrhJsqehIxjuUQ93Fqx6gmo4cDgn5srW5dedvMbqD0="
      binary_cache_url        = "https://ghaf-binary-cache-${local.ws}.${azurerm_resource_group.infra.location}.cloudapp.azure.com"
    }
  }

  # Read ssh-keys.yaml into local.ssh_keys
  ssh_keys = yamldecode(file("../ssh-keys.yaml"))

  # This determines the configuration options used in the
  # ghaf-infra instance (defines e.g. vm_sizes and number of builders).
  # If workspace name is "dev" or "prod" use the workspace name as
  # envtype, otherwise, use the value from var.envtype.
  conf = local.ws == "dev" || local.ws == "prod" ? local.ws : var.envtype

  # Selects the persistent data (see ./persistent) used in the ghaf-infra
  # instance; currently either "dev" or "prod" based on the environment type:
  #   "priv" ==> "dev"
  #   "dev"  ==> "dev"
  #   "prod" ==> "prod"
  persistent_data = local.conf == "priv" ? "dev" : local.conf
}

################################################################################

# Resource group for this ghaf-infra instance
resource "azurerm_resource_group" "infra" {
  name     = "ghaf-infra-${local.ws}"
  location = data.azurerm_storage_account.tfstate.location
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

# Slice out a subnet for the builders
resource "azurerm_subnet" "builders" {
  name                 = "ghaf-infra-builders"
  resource_group_name  = azurerm_resource_group.infra.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.4.0/28"]
}

################################################################################

# Storage account and storage container used to store VM images

resource "azurerm_storage_account" "vm_images" {
  name                            = "img${local.ws}${local.shortloc}"
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

# Data sources to access state data, see ./state-storage

data "azurerm_storage_account" "tfstate" {
  name                = local.envs["storage_account_name"]
  resource_group_name = local.envs["storage_account_rg_name"]
}

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

# Data sources to access 'workspace-specific persistent' data
# see: ./persistent/workspace-specific

data "azurerm_managed_disk" "binary_cache_caddy_state" {
  name                = "binary-cache-vm-caddy-state-${local.ws}"
  resource_group_name = "ghaf-infra-persistent-${local.shortloc}"
}

data "azurerm_managed_disk" "jenkins_controller_caddy_state" {
  name                = "jenkins-controller-vm-caddy-state-${local.ws}"
  resource_group_name = "ghaf-infra-persistent-${local.shortloc}"
}

################################################################################
