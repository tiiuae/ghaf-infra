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
  # Backend for storing terraform state (see ../state-storage)
  backend "azurerm" {
    resource_group_name  = "ghaf-infra-state"
    storage_account_name = "ghafinfratfstatestorage"
    container_name       = "ghaf-infra-tfstate-container"
    key                  = "ghaf-azarm.tfstate"
  }
}
provider "azurerm" {
  features {}
}
# Sops secrets
data "sops_file" "secrets" {
  source_file = "secrets.yaml"
}
# Resource group
resource "azurerm_resource_group" "rg" {
  name     = "ghaf-azarm-arm-builder"
  location = "northeurope"
}
# Virtual Network
resource "azurerm_virtual_network" "ghaf_infra_tf_vnet" {
  name                = "ghaf-infra-tf-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}
# Subnet
resource "azurerm_subnet" "ghaf_infra_tf_subnet" {
  name                 = "ghaf-infra-tf-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.ghaf_infra_tf_vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

################################################################################

# azarm:
# aarch64-linux builder - Ubuntu host with nix package manager.
# Why not NixOS? The reason is: we have not managed to get nixos-anywhere
# working with azure arm VMs.
# Since the host is not NixOS, all the host configuration is done on
# terraform apply using the configuration script at ./ubuntu-builder.sh

# Public IP
resource "azurerm_public_ip" "azarm_public_ip" {
  name                = "azarm-public-ip"
  domain_name_label   = "azarm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}
# Network interface
resource "azurerm_network_interface" "azarm_ni" {
  name                = "azarm-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_configuration {
    name                          = "azarm_nic_configuration"
    subnet_id                     = azurerm_subnet.ghaf_infra_tf_subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.2.10"
    public_ip_address_id          = azurerm_public_ip.azarm_public_ip.id
  }
}
# Network Security Group
resource "azurerm_network_security_group" "azarm_nsg" {
  name                = "azarm-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  security_rule {
    name                       = "AllowSSHInbound"
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
resource "azurerm_network_interface_security_group_association" "nsg_azarm_apply" {
  network_interface_id      = azurerm_network_interface.azarm_ni.id
  network_security_group_id = azurerm_network_security_group.azarm_nsg.id
}
# Azure arm builder (azarm)
resource "azurerm_linux_virtual_machine" "azarm_vm" {
  name                = "azarm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  network_interface_ids = [
    azurerm_network_interface.azarm_ni.id
  ]
  size = "Standard_D8ps_v5"
  os_disk {
    name                 = "azarm-disk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 512
  }
  source_image_reference {
    publisher = "canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-arm64"
    version   = "latest"
  }
  admin_username                  = data.sops_file.secrets.data["vm_admin_name"]
  disable_password_authentication = true
  admin_ssh_key {
    username   = data.sops_file.secrets.data["vm_admin_name"]
    public_key = data.sops_file.secrets.data["vm_admin_rsa_pub"]
  }
}
resource "azurerm_virtual_machine_extension" "deploy_ubuntu_builder" {
  name                 = "azarm-vmext"
  virtual_machine_id   = azurerm_linux_virtual_machine.azarm_vm.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"
  settings             = <<EOF
    {
        "script": "${base64encode(file("./ubuntu-builder.sh"))}"
    }
    EOF
}

################################################################################