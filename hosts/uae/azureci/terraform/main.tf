# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
}

# Resource group for ghaf-infra
resource "azurerm_resource_group" "infra" {
  name     = "rg-uaenorth-${var.resource_tags["env"]}-${var.resource_tags["project"]}-ghaf-infra-ci"
  location = "me-central-1"
}

# Virtual network for ghaf-infra
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-uaenorth-${var.resource_tags["env"]}-${var.resource_tags["project"]}-ghaf-infra"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.infra.location
  resource_group_name = azurerm_resource_group.infra.name
}

# Jenkins network configuration
# Subnet for jenkins
resource "azurerm_subnet" "jenkins" {
  name                 = "snet-uaenorth-${var.resource_tags["env"]}-${var.resource_tags["project"]}-ghaf-infra-jenkins"
  resource_group_name  = azurerm_resource_group.infra.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Public IP for jenkins
resource "azurerm_public_ip" "jenkins" {
  name                = "pip-uaenorth-${var.resource_tags["env"]}-${var.resource_tags["project"]}-ghaf-infra-jenkins"
  resource_group_name = azurerm_resource_group.infra.name
  location            = azurerm_resource_group.infra.location
  allocation_method   = "Static"
}

# NIC for jenkins
resource "azurerm_network_interface" "jenkins" {
  name                = "nic-uaenorth-${var.resource_tags["env"]}-${var.resource_tags["project"]}-ghaf-infra-jenkins"
  resource_group_name = azurerm_resource_group.infra.name
  location            = azurerm_resource_group.infra.location

  ip_configuration {
    name                          = "jenkins"
    subnet_id                     = azurerm_subnet.jenkins.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jenkins.id
  }
}

# Builder network configuration
# Subnet for builders
resource "azurerm_subnet" "builders" {
  name                 = "snet-uaenorth-${var.resource_tags["env"]}-${var.resource_tags["project"]}-ghaf-infra-builders"
  resource_group_name  = azurerm_resource_group.infra.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Subnet for builders
resource "azurerm_subnet" "builders" {
  name                 = "snet-uaenorth-${var.resource_tags["env"]}-${var.resource_tags["project"]}-ghaf-infra-builders"
  resource_group_name  = azurerm_resource_group.infra.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Public IP for builder-x86-1
resource "azurerm_public_ip" "builder-x86-1" {
  name                = "pip-uaenorth-${var.resource_tags["env"]}-${var.resource_tags["project"]}-ghaf-infra-builder-x86-1"
  resource_group_name = azurerm_resource_group.infra.name
  location            = azurerm_resource_group.infra.location
  allocation_method   = "Static"
}

# NIC for builder-x86-1
resource "azurerm_network_interface" "builder-x86-1" {
  name                = "nic-uaenorth-${var.resource_tags["env"]}-${var.resource_tags["project"]}-ghaf-infra-x86-1"
  resource_group_name = azurerm_resource_group.infra.name
  location            = azurerm_resource_group.infra.location

  ip_configuration {
    name                          = "builder-x86-1"
    subnet_id                     = azurerm_subnet.builders.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.builder-x86-1.id
  }
}


# Jenkins configuration
# Virtual Machine
resource "azurerm_linux_virtual_machine" "jenkins" {
  name                            = "vm-uaenorth-${var.resource_tags["env"]}-${var.resource_tags["project"]}-ghaf-infra-jenkins"
  resource_group_name             = azurerm_resource_group.infra.name
  location                        = azurerm_resource_group.infra.location
  size                            = "Standard_B16sv2"
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.jenkins.id,
  ]

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }
}

resource "azurerm_network_security_group" "jenkins" {
  name                = "nsg-uaenorth-${var.resource_tags["env"]}-${var.resource_tags["project"]}-ghaf-infra-jenkins"
  location            = azurerm_resource_group.infra.location
  resource_group_name = azurerm_resource_group.infra.name
  security_rule {
    access                     = "Allow"
    direction                  = "Inbound"
    name                       = "https"
    priority                   = 100
    protocol                   = "Tcp"
    source_port_range          = "*"
    source_address_prefix      = "*"
    destination_port_range     = "443"
    destination_address_prefix = "azurerm_subnet.jenkins.address_prefix"
  }
  security_rule {
    access                     = "Allow"
    direction                  = "Inbound"
    name                       = "http"
    priority                   = 200
    protocol                   = "Tcp"
    source_port_range          = "*"
    source_address_prefix      = "*"
    destination_port_range     = "80"
    destination_address_prefix = "azurerm_subnet.jenkins.address_prefix"
  }
  security_rule {
    access                     = "Allow"
    direction                  = "Inbound"
    name                       = "nebula"
    priority                   = 300
    protocol                   = "Any"
    source_port_range          = "*"
    source_address_prefix      = "109.204.204.138,109.204.227.78,213.42.107.24,83.110.0.255"
    destination_port_range     = "Any"
    destination_address_prefix = "azurerm_subnet.jenkins.address_prefix"
  }
}

# Builder configuration
# Virtual Machine
resource "azurerm_linux_virtual_machine" "builder-x86-1" {
  name                            = "vm-uaenorth-${var.resource_tags["env"]}-${var.resource_tags["project"]}-ghaf-infra-builder-x86-1"
  resource_group_name             = azurerm_resource_group.infra.name
  location                        = azurerm_resource_group.infra.location
  size                            = "Standard_B32asv2"
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.builders.id,
  ]

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }
}

resource "azurerm_network_security_group" "builder-x86-1" {
  name                = "nsg-uaenorth-${var.resource_tags["env"]}-${var.resource_tags["project"]}-ghaf-infra-builder-x86-1"
  location            = azurerm_resource_group.infra.location
  resource_group_name = azurerm_resource_group.infra.name
  security_rule {
    access                     = "Allow"
    direction                  = "Inbound"
    name                       = "ssh"
    priority                   = 100
    protocol                   = "Tcp"
    source_port_range          = "*"
    source_address_prefix      = "*"
    destination_port_range     = "22"
    destination_address_prefix = "azurerm_subnet.builder-x86-1.address_prefix"
  }
}

# Registry  configuration
# Virtual Machine
resource "azurerm_linux_virtual_machine" "registry" {
  name                            = "vm-uaenorth-${var.resource_tags["env"]}-${var.resource_tags["project"]}-ghaf-infra-registry"
  resource_group_name             = azurerm_resource_group.infra.name
  location                        = azurerm_resource_group.infra.location
  size                            = "Standard_B4sv2"
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.registry.id,
  ]

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }
}

# NSG rules
resource "azurerm_network_security_group" "registry" {
  name                = "nsg-uaenorth-${var.resource_tags["env"]}-${var.resource_tags["project"]}-ghaf-infra-registry"
  location            = azurerm_resource_group.infra.location
  resource_group_name = azurerm_resource_group.infra.name
  security_rule {
    access                     = "Allow"
    direction                  = "Inbound"
    name                       = "ssh"
    priority                   = 100
    protocol                   = "Tcp"
    source_port_range          = "*"
    source_address_prefix      = "*"
    destination_port_range     = "22"
    destination_address_prefix = "azurerm_subnet.registry.address_prefix"
  }
  security_rule {
    access                     = "Allow"
    direction                  = "Inbound"
    name                       = "zot"
    priority                   =  200
    protocol                   = "Tcp"
    source_port_range          = "*"
    source_address_prefix      = "*"
    destination_port_range     = "80,443,5000"
    destination_address_prefix = "azurerm_subnet.registry.address_prefix"
  }
}
