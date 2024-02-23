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
  }
}

################################################################################

terraform {
  # Backend for storing terraform state (see ../../state-storage)
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
variable "persistent_resource_group" {
  type        = string
  default     = "ghaf-infra-persistent-eun"
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

resource "azurerm_managed_disk" "binary_cache_caddy_state" {
  name                 = "binary-cache-vm-caddy-state-${local.ws}"
  resource_group_name  = data.azurerm_resource_group.persistent.name
  location             = data.azurerm_resource_group.persistent.location
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 1
}

resource "azurerm_managed_disk" "jenkins_controller_caddy_state" {
  name                 = "jenkins-controller-vm-caddy-state-${local.ws}"
  resource_group_name  = data.azurerm_resource_group.persistent.name
  location             = data.azurerm_resource_group.persistent.location
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 1
}

################################################################################
