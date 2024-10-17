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
