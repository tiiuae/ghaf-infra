# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

provider "azurerm" {
  # https://github.com/hashicorp/terraform-provider-azurerm/issues/24804
  skip_provider_registration = true
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
  # Backend for storing terraform state (see ../../state-storage)
  backend "azurerm" {
    # resource_group_name and storage_account_name are set by the callee
    # from command line in terraform init, see terraform-init.sh
    container_name = "ghaf-infra-tfstate-container"
    key            = "ghaf-infra-persistent.tfstate"
  }
}

################################################################################

# Variables
variable "persistent_resource_group" {
  type        = string
  description = "Parent resource group name"
}

locals {
  # Raise an error if workspace is 'default',
  # this is a workaround to missing asserts in terraform:
  assert_workspace_not_default = regex(
    (terraform.workspace == "default") ?
  "((Force invalid regex pattern)\n\nERROR: workspace 'default' is not allowed" : "", "")

  # Sanitize workspace name:
  ws = substr(replace(lower(terraform.workspace), "/[^a-z0-9]/", ""), 0, 16)
}

# Data source to access persistent resource group (see ../main.tf)
data "azurerm_resource_group" "persistent" {
  name = var.persistent_resource_group
}

# Current signed-in user
data "azurerm_client_config" "current" {}


################################################################################

# Resources

# secret_resource must be created on import, e.g.:
#
#   nix-store --generate-binary-cache-key foo secret-key public-key
#   terraform import secret_resource.binary_cache_signing_key "$(< ./secret-key)"
#   terraform apply
#
# Ghaf-infra automates the creation in 'terraform-init.sh'
resource "secret_resource" "binary_cache_signing_key" {
  lifecycle {
    prevent_destroy = true
  }
}
resource "secret_resource" "binary_cache_signing_key_pub" {
}

module "binary_cache_sigkey" {
  source = "../binary-cache-sigkey"
  # Must be globally unique, max 24 characters
  bincache_keyvault_name = "bchek-id0${local.ws}"
  signing_key            = secret_resource.binary_cache_signing_key
  signing_key_pub        = secret_resource.binary_cache_signing_key_pub
  resource_group_name    = data.azurerm_resource_group.persistent.name
  location               = data.azurerm_resource_group.persistent.location
  tenant_id              = data.azurerm_client_config.current.tenant_id
  object_id              = data.azurerm_client_config.current.object_id
}

module "binary_cache_storage" {
  source = "../binary-cache-storage"
  # Must be globally unique, max 24 characters
  bincache_storage_account_name = "bchesid0${local.ws}"
  resource_group_name           = data.azurerm_resource_group.persistent.name
  location                      = data.azurerm_resource_group.persistent.location
}

################################################################################
