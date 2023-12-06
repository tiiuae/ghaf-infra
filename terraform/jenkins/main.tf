# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

provider "azurerm" {
  features {}
}

# read ssh-keys.yaml into local.ssh_keys
locals {
  ssh_keys = yamldecode(file("../../ssh-keys.yaml"))
}

# The resource group everything in this terraform module lives in
resource "azurerm_resource_group" "default" {
  name     = "ghaf-infra-jenkins"
  location = "northeurope"
}

# Create a virtual network and slice out a subnet for jenkins.
resource "azurerm_virtual_network" "vnet" {
  name                = "ghaf-infra-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
}

resource "azurerm_subnet" "jenkins" {
  name                 = "ghaf-infra-jenkins"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}
