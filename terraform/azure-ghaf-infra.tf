# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    sops = {
      source = "carlpett/sops"
    }
  }
}

data "sops_file" "ghaf-infra" {
  source_file = "secrets.yaml"
}

provider "azurerm" {
  subscription_id = data.sops_file.ghaf-infra.data["az_subscription_id"]
  client_id       = data.sops_file.ghaf-infra.data["az_client_id"]
  client_secret   = data.sops_file.ghaf-infra.data["az_client_secret"]
  tenant_id       = data.sops_file.ghaf-infra.data["az_tenant_id"]
  features {}
}

variable "resource_group_location" {
  type        = string
  default     = "northeurope"
  description = "Location of the resource group."
}

resource "azurerm_resource_group" "rg" {
  location = var.resource_group_location
  name     = "ghaf-infra-terraform-test"
}