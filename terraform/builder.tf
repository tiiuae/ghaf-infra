# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

module "builder_image" {
  source = "./modules/azurerm-nix-vm-image"

  nix_attrpath   = "outputs.nixosConfigurations.builder.config.system.build.azureImage"
  nix_entrypoint = "${path.module}/.."

  name                   = "builder"
  resource_group_name    = azurerm_resource_group.infra.name
  location               = azurerm_resource_group.infra.location
  storage_account_name   = azurerm_storage_account.vm_images.name
  storage_container_name = azurerm_storage_container.vm_images.name
}

locals {
  num_builders = local.opts[local.conf].num_builders
}

module "builder_vm" {
  source = "./modules/azurerm-linux-vm"

  count = local.num_builders

  resource_group_name          = azurerm_resource_group.infra.name
  location                     = azurerm_resource_group.infra.location
  virtual_machine_name         = "ghaf-builder-${count.index}-${local.env}"
  virtual_machine_size         = local.opts[local.conf].vm_size_builder
  virtual_machine_source_image = module.builder_image.image_id

  virtual_machine_custom_data = join("\n", ["#cloud-config", yamlencode({
    users = [{
      name = "remote-build"
      ssh_authorized_keys = [
        "${data.azurerm_key_vault_secret.ssh_remote_build_pub.value}"
      ]
    }]
    write_files = [
      {
        content = "AZURE_STORAGE_ACCOUNT_NAME=${data.azurerm_storage_account.binary_cache.name}",
        "path"  = "/var/lib/rclone-http/env"
      }
    ],
  })])

  subnet_id = azurerm_subnet.builders.id
}

# Allow inbound SSH from the jenkins subnet (only)
resource "azurerm_network_interface_security_group_association" "builder_vm" {
  count = local.num_builders

  network_interface_id      = module.builder_vm[count.index].virtual_machine_network_interface_id
  network_security_group_id = azurerm_network_security_group.builder_vm[count.index].id
}

resource "azurerm_network_security_group" "builder_vm" {
  count = local.num_builders

  name                = "builder-vm-${count.index}"
  resource_group_name = azurerm_resource_group.infra.name
  location            = azurerm_resource_group.infra.location

  security_rule {
    name                       = "AllowSSHFromJenkins"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = [22]
    source_address_prefix      = azurerm_subnet.jenkins.address_prefixes[0]
    destination_address_prefix = "*"
  }
}

# Allow the VMs to read from the binary cache bucket
resource "azurerm_role_assignment" "builder_access_binary_cache" {
  count                = local.num_builders
  scope                = data.azurerm_storage_container.binary_cache_1.resource_manager_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = module.builder_vm[count.index].virtual_machine_identity_principal_id
}
