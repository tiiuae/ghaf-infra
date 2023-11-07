# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
# Resource group
resource "azurerm_resource_group" "ghaf_infra_tf_dev" {
  name     = "ghaf-infra-tf-dev"
  location = var.resource_group_location
}
# Create VN
resource "azurerm_virtual_network" "ghaf_infra_tf_vnet" {
  name                = "ghaf-infra-tf-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.resource_group_location
  resource_group_name = azurerm_resource_group.ghaf_infra_tf_dev.name
}
# Create Subnet
resource "azurerm_subnet" "ghaf_infra_tf_subnet" {
  name                 = "ghaf-infra-tf-subnet"
  resource_group_name  = azurerm_resource_group.ghaf_infra_tf_dev.name
  virtual_network_name = azurerm_virtual_network.ghaf_infra_tf_vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}
# Network interface
resource "azurerm_network_interface" "ghaf_infra_tf_network_interface" {
  name                = "ghaf-infratf286-z1"
  location            = var.resource_group_location
  resource_group_name = azurerm_resource_group.ghaf_infra_tf_dev.name
  ip_configuration {
    name                          = "my_nic_configuration"
    subnet_id                     = azurerm_subnet.ghaf_infra_tf_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ghaf_infra_tf_public_ip.id
  }
}
# Create Availability Set
resource "azurerm_availability_set" "ghaf_infra_tf_availability_set" {
  name                         = "ghaf-infra-tf-availability-set"
  location                     = var.resource_group_location
  resource_group_name          = azurerm_resource_group.ghaf_infra_tf_dev.name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
}
# Create Public IPs
resource "azurerm_public_ip" "ghaf_infra_tf_public_ip" {
  name                = "ghaf-infra-tf-public-ip"
  location            = var.resource_group_location
  resource_group_name = azurerm_resource_group.ghaf_infra_tf_dev.name
  allocation_method   = "Dynamic"
}
# Create Network Security Group and rule
resource "azurerm_network_security_group" "ghaf_infra_tf_nsg" {
  name                = "ghaf-infra-tf-nsg"
  location            = var.resource_group_location
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
# Create Linux Virtual Machine
resource "azurerm_linux_virtual_machine" "ghafinfra_tf" {
  name                = "ghafinfratf"
  location            = var.resource_group_location
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
  admin_username                  = "karim"
  disable_password_authentication = true
  admin_ssh_key {
    username   = "karim"
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDe5L8iOqhNPsYz5eh9Bz/URYguG60JjMGmKG0wwLIb6Gf2M8Txzk24ESGbMR/F5RYsV1yWYOocL47ngDWQIbO6MGJ7ftUr7slWoUA/FSVwh/jsG681mRqIuJXjKM/YQhBkI9k6+eVxRfLDTs5XZfbwdm7T4aP8ZI2609VY0guXfa/F7DSE1BxN7IJMn0CWLQJanBpoYUxqyQXCUXgljMokdPjTrqAxlBluMsVTP+ZKDnjnpHcVE/hCKk5BxaU6K97OdeIOOEWXAd6uEHssomjtU7+7dhiZzjhzRPKDiSJDF9qtIw50kTHz6ZTdH8SAZmu0hsS6q8OmmDTAnt24dFJV karim@nixos"
  }

}