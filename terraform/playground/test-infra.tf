# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
  # Backend for storing tfstate (see ./azure-storage)
  backend "azurerm" {
    resource_group_name  = "ghaf-infra-storage"
    storage_account_name = "ghafinfrastatestorage"
    container_name       = "ghaf-infra-tfstate-container"
    key                  = "ghaf-infra-playground.tfstate"
  }
}
provider "azurerm" {
  features {}
}
# Resource group
resource "azurerm_resource_group" "playground_rg" {
  name     = "ghaf-infra-playground-${terraform.workspace}"
  location = "northeurope"
}
# Virtual Network
resource "azurerm_virtual_network" "ghaf_infra_tf_vnet" {
  name                = "ghaf-infra-tf-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.playground_rg.location
  resource_group_name = azurerm_resource_group.playground_rg.name
}
# Subnet
resource "azurerm_subnet" "playground_subnet" {
  name                 = "ghaf-infra-tf-subnet"
  resource_group_name  = azurerm_resource_group.playground_rg.name
  virtual_network_name = azurerm_virtual_network.ghaf_infra_tf_vnet.name
  address_prefixes     = ["10.0.5.0/24"]
}
# read ssh-keys.yaml into local.ssh_keys
locals {
  ssh_keys = yamldecode(file("../../ssh-keys.yaml"))
}

################################################################################

# Image storage

# Create a random string
resource "random_string" "imgstr" {
  length  = "12"
  special = "false"
  upper   = false
}

resource "azurerm_storage_account" "vm_images" {
  name                            = "nixosimages${random_string.imgstr.result}"
  resource_group_name             = azurerm_resource_group.playground_rg.name
  location                        = azurerm_resource_group.playground_rg.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
}

resource "azurerm_storage_container" "vm_images" {
  name                  = "ghaf-test-vm-images"
  storage_account_name  = azurerm_storage_account.vm_images.name
  container_access_type = "private"
}

################################################################################

# VM

module "test_image" {
  source = "../../tf-modules/azurerm-nix-vm-image"

  nix_attrpath   = "outputs.nixosConfigurations.builder.config.system.build.azureImage"
  nix_entrypoint = "${path.module}/../.."

  name                = "playground_vm_img"
  resource_group_name = azurerm_resource_group.playground_rg.name
  location            = azurerm_resource_group.playground_rg.location

  storage_account_name   = azurerm_storage_account.vm_images.name
  storage_container_name = azurerm_storage_container.vm_images.name
}

locals {
  num_vms = 1
}

module "test_vm" {
  source = "../../tf-modules/azurerm-linux-vm"

  count = local.num_vms

  resource_group_name = azurerm_resource_group.playground_rg.name
  location            = azurerm_resource_group.playground_rg.location

  virtual_machine_name = "ghaf-playground-${count.index}-${terraform.workspace}"
  # Demonstrate a way to use different configurations in different workspaces.
  # Here, we define the following image sizes:
  # - Use 'Standard_D2_v2' if the workspace is 'default' (2 vCPUs, 7 GiB RAM)
  # - Use 'Standard_D1_v2' if the workspace is anything but 'default' (1 vCPU, 3.5 GiB RAM)
  # The idea is based on the following article:
  # https://blog.gruntwork.io/how-to-manage-multiple-environments-with-terraform-using-workspaces-98680d89a03e#2bc6
  #
  # Full list of Azure image sizes are available in:
  # https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux/#pricing
  virtual_machine_size         = terraform.workspace == "default" ? "Standard_D2_v2" : "Standard_D1_v2"
  virtual_machine_source_image = module.test_image.image_id

  virtual_machine_custom_data = join("\n", ["#cloud-config", yamlencode({
    users = [
      {
        name                = "hrosten"
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        ssh_authorized_keys = local.ssh_keys["hrosten"]
      },
    ]
  })])

  allocate_public_ip = true
  subnet_id          = azurerm_subnet.playground_subnet.id
}

# Allow inbound SSH
resource "azurerm_network_security_group" "test_vm" {
  count               = local.num_vms
  name                = "test-vm-${count.index}"
  resource_group_name = azurerm_resource_group.playground_rg.name
  location            = azurerm_resource_group.playground_rg.location
  security_rule {
    name                       = "AllowSSH"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = [22]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
resource "azurerm_network_interface_security_group_association" "test_vm" {
  count                     = local.num_vms
  network_interface_id      = module.test_vm[count.index].virtual_machine_network_interface_id
  network_security_group_id = azurerm_network_security_group.test_vm[count.index].id
}

################################################################################

