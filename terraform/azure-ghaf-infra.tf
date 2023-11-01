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
  features {}
}


# Backend for storing tfstate

terraform {
  backend "azurerm" {
    resource_group_name  = "ghaf-infra-storage"
    storage_account_name = "ghafinfrastatestorage"
    container_name       = "ghaf-infra-tfstate-container"
    key                  = "ghaf-infra.tfstate"
  }
}


# Resource group

variable "resource_group_location" {
  type        = string
  default     = "northeurope"
  description = "Location of the resource group."
}

resource "azurerm_resource_group" "rg" {
  name     = "ghaf-infra-terraform-dev"
  location = var.resource_group_location
}
