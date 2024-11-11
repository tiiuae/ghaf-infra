# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

locals {
  arm_num_builders = local.opts[local.conf].num_builders_aarch64
  # Hard-code the arm builder location to 'northeurope' due to limited support
  # of arm-based VMs in (many) Azure regions. For reference, see:
  # https://github.com/tiiuae/ghaf-infra/pull/81#pullrequestreview-1927417660
  arm_vm_location = "northeurope"
  # Is the rest of the infra also being deployed to 'northeurope'?
  infra_in_eun = azurerm_resource_group.infra.location == "northeurope"
  # If all resources are deployed to 'northeurope', jenkins-controller will
  # access the arm builder over the private network. If the rest of the infra
  # is not deployed in 'northeurope', jenkins-controller will access the arm
  # builder VM over the public network.
  allow_ssh_from = local.infra_in_eun ? azurerm_subnet.jenkins.address_prefixes[0] : module.jenkins_controller_vm.virtual_machine_ip_address
  # If all resources are deployed to 'northeurope', deploy all VMs on the
  # same subnet. If the rest of the infra is not deployed in 'northeurope'
  # deploy the arm builder in its own subnet.
  subnet_id = local.infra_in_eun ? azurerm_subnet.builders.id : azurerm_subnet.builders_arm[0].id
}

resource "azurerm_virtual_network" "vnet_arm" {
  count               = local.infra_in_eun ? 0 : 1
  name                = "ghaf-infra-vnet-arm"
  address_space       = ["10.0.0.0/16"]
  location            = local.arm_vm_location
  resource_group_name = azurerm_resource_group.infra.name
}

resource "azurerm_subnet" "builders_arm" {
  count                = local.infra_in_eun ? 0 : 1
  name                 = "ghaf-infra-builders-arm"
  resource_group_name  = azurerm_resource_group.infra.name
  virtual_network_name = azurerm_virtual_network.vnet_arm[0].name
  address_prefixes     = ["10.0.4.0/28"]
}

module "arm_builder_vm" {
  source = "./modules/arm-builder-vm"

  count = local.arm_num_builders

  resource_group_name         = azurerm_resource_group.infra.name
  location                    = local.arm_vm_location
  virtual_machine_name        = "ghaf-builder-aarch64-${count.index}-${local.ws}"
  virtual_machine_size        = local.opts[local.conf].vm_size_builder_aarch64
  virtual_machine_osdisk_size = local.opts[local.conf].osdisk_size_builder
  binary_cache_public_key     = local.binary_cache_public_key

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

  # Currently, we always deploy arm builder VMs to location 'northeurope'.
  # In case other resources in this infra (namely, the jenkins-controller VM)
  # are deployed to location other than 'northeurope', jenkins-controller
  # cannot access the arm builder using its private IP. Therefore, when the arm
  # builder and jenkins-controller are deployed on different locations, builder
  # needs to be accessed over its public IP.
  access_over_public_ip = !(local.infra_in_eun)
  subnet_id             = local.subnet_id
}

# Allow inbound SSH from the jenkins subnet (only)
resource "azurerm_network_interface_security_group_association" "arm_builder_vm" {
  count = local.arm_num_builders

  network_interface_id      = module.arm_builder_vm[count.index].virtual_machine_network_interface_id
  network_security_group_id = azurerm_network_security_group.arm_builder_vm[count.index].id
}

resource "azurerm_network_security_group" "arm_builder_vm" {
  count = local.arm_num_builders

  name                = "arm-builder-vm-${local.shortloc}-${count.index}"
  resource_group_name = azurerm_resource_group.infra.name
  location            = local.arm_vm_location

  security_rule {
    name                       = "AllowSSHFromJenkins"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = [22]
    source_address_prefix      = local.allow_ssh_from
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
