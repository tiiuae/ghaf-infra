# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

# Resource group
resource "azurerm_resource_group" "rg" {
  name     = "ghaf-infra-terraform-dev"
  location = var.resource_group_location
}
# Create  VN
resource "azurerm_virtual_network" "ghaf-infra-vnet" {
  name                = "ghaf-infra-terraform-dev-vnet"
  address_space       = ["10.3.0.0/24"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}


# Create public IPs
resource "azurerm_public_ip" "ghafhydra_terraform_public_ip" {
  name                = "ghaf-infra-terraform-dev-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}


# Create Network SG and rule
resource "azurerm_network_security_group" "ghafhydra_terraform_nsg" {
  name                = "ghaf-infra-terraform-dev-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

