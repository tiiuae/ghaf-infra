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
provider "azurerm" {
  features {}
}
# Sops secrets
data "sops_file" "ghaf_infra" {
  source_file = "secrets.yaml"
}
# Backend for storing tfstate (see ./azure-storage)
terraform {
  backend "azurerm" {
    resource_group_name  = "ghaf-infra-storage"
    storage_account_name = "ghafinfrastatestorage"
    container_name       = "ghaf-infra-tfstate-container"
    key                  = "ghaf-infra.tfstate"
  }
}
# Resource group
resource "azurerm_resource_group" "ghaf_infra_tf_dev" {
  name     = "ghaf-infra-tf-dev"
  location = "swedencentral"
}
# Virtual Network
resource "azurerm_virtual_network" "ghaf_infra_tf_vnet" {
  name                = "ghaf-infra-tf-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.ghaf_infra_tf_dev.location
  resource_group_name = azurerm_resource_group.ghaf_infra_tf_dev.name
}
# Subnet
resource "azurerm_subnet" "ghaf_infra_tf_subnet" {
  name                 = "ghaf-infra-tf-subnet"
  resource_group_name  = azurerm_resource_group.ghaf_infra_tf_dev.name
  virtual_network_name = azurerm_virtual_network.ghaf_infra_tf_vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}
# Network interface
resource "azurerm_network_interface" "ghaf_infra_tf_network_interface" {
  name                = "ghaf-infratf286-z1"
  location            = azurerm_resource_group.ghaf_infra_tf_dev.location
  resource_group_name = azurerm_resource_group.ghaf_infra_tf_dev.name
  ip_configuration {
    name                          = "my_nic_configuration"
    subnet_id                     = azurerm_subnet.ghaf_infra_tf_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ghaf_infra_tf_public_ip.id
  }
}
# Availability Set
resource "azurerm_availability_set" "ghaf_infra_tf_availability_set" {
  name                         = "ghaf-infra-tf-availability-set"
  location                     = azurerm_resource_group.ghaf_infra_tf_dev.location
  resource_group_name          = azurerm_resource_group.ghaf_infra_tf_dev.name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
}
# Public IPs
resource "azurerm_public_ip" "ghaf_infra_tf_public_ip" {
  name                = "ghaf-infra-tf-public-ip"
  location            = azurerm_resource_group.ghaf_infra_tf_dev.location
  resource_group_name = azurerm_resource_group.ghaf_infra_tf_dev.name
  allocation_method   = "Dynamic"
}
# Network Security Group and Rule
resource "azurerm_network_security_group" "ghaf_infra_tf_nsg" {
  name                = "ghaf-infra-tf-nsg"
  location            = azurerm_resource_group.ghaf_infra_tf_dev.location
  resource_group_name = azurerm_resource_group.ghaf_infra_tf_dev.name
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
# Example Linux Virtual Machine
resource "azurerm_linux_virtual_machine" "ghafinfra_tf" {
  name                = "ghafinfratf"
  location            = azurerm_resource_group.ghaf_infra_tf_dev.location
  resource_group_name = azurerm_resource_group.ghaf_infra_tf_dev.name
  availability_set_id = azurerm_availability_set.ghaf_infra_tf_availability_set.id
  network_interface_ids = [
    azurerm_network_interface.ghaf_infra_tf_network_interface.id
  ]
  size = "Standard_B8ms"
  os_disk {
    name                 = "ghafinfratfdisk1"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 512
  }
  source_image_reference {
    publisher = "canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  admin_username                  = data.sops_file.ghaf_infra.data["vm_admin_name"]
  disable_password_authentication = true
  admin_ssh_key {
    username = data.sops_file.ghaf_infra.data["vm_admin_name"]
    # Azure requires RSA keys:
    # https://learn.microsoft.com/troubleshoot/azure/virtual-machines/ed25519-ssh-keys
    public_key = data.sops_file.ghaf_infra.data["vm_admin_rsa_pub"]
  }
}