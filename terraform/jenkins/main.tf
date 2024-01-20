# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
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

locals {
  # read ssh-keys.yaml into local.ssh_keys
  ssh_keys = yamldecode(file("../../ssh-keys.yaml"))
  # postfix used in the resource group name
  rg_postfix = terraform.workspace == "default" ? "prod" : terraform.workspace
  # postfix used in various resource names
  name_postfix = terraform.workspace == "default" ? "ghafprod" : terraform.workspace
}

# The resource group everything in this terraform module lives in
resource "azurerm_resource_group" "default" {
  name     = "ghaf-infra-jenkins-${local.rg_postfix}"
  location = "northeurope"
}

# Create a virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "ghaf-infra-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
}

# Slice out a subnet for jenkins.
resource "azurerm_subnet" "jenkins" {
  name                 = "ghaf-infra-jenkins"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Slice out a subnet for the buidlers.
resource "azurerm_subnet" "builders" {
  name                 = "ghaf-infra-builders"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.4.0/28"]
}
