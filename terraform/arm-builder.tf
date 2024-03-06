# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

locals {
  arm_num_builders = local.opts[local.conf].num_builders_aarch64
}

module "arm_builder_vm" {
  source = "./modules/arm-builder-vm"

  count = local.arm_num_builders

  resource_group_name         = azurerm_resource_group.infra.name
  location                    = azurerm_resource_group.infra.location
  virtual_machine_name        = "ghaf-builder-aarch64-${count.index}-${local.ws}"
  virtual_machine_size        = local.opts[local.conf].vm_size_builder_aarch64
  virtual_machine_osdisk_size = local.opts[local.conf].osdisk_size_builder

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
resource "azurerm_network_interface_security_group_association" "arm_builder_vm" {
  count = local.arm_num_builders

  network_interface_id      = module.arm_builder_vm[count.index].virtual_machine_network_interface_id
  network_security_group_id = azurerm_network_security_group.arm_builder_vm[count.index].id
}

resource "azurerm_network_security_group" "arm_builder_vm" {
  count = local.arm_num_builders

  name                = "arm-builder-vm-${count.index}"
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
resource "azurerm_role_assignment" "arm_builder_access_binary_cache" {
  count                = local.arm_num_builders
  scope                = data.azurerm_storage_container.binary_cache_1.resource_manager_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = module.arm_builder_vm[count.index].virtual_machine_identity_principal_id
}
