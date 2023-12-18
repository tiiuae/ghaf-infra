# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

module "binary_cache_image" {
  source = "../../tf-modules/azurerm-nix-vm-image"

  nix_attrpath   = "outputs.nixosConfigurations.binary-cache.config.system.build.azureImage"
  nix_entrypoint = "${path.module}/../.."


  name                = "binary-cache"
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location

  storage_account_name   = azurerm_storage_account.vm_images.name
  storage_container_name = azurerm_storage_container.vm_images.name
}

module "binary_cache_vm" {
  source = "../../tf-modules/azurerm-linux-vm"

  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location

  virtual_machine_name         = "ghaf-binary-cache"
  virtual_machine_size         = "Standard_D1_v2"
  virtual_machine_source_image = module.binary_cache_image.image_id

  virtual_machine_custom_data = join("\n", ["#cloud-config", yamlencode({
    users = [
      for user in toset(["bmg", "flokli", "hrosten"]) : {
        name                = user
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        ssh_authorized_keys = local.ssh_keys[user]
      }
    ]
    # See corresponding EnvironmentFile= directives in services
    write_files = [
      {
        content = "AZURE_STORAGE_ACCOUNT_NAME=${azurerm_storage_account.binary_cache.name}",
        "path"  = "/var/lib/rclone-http/env"
      },
      {
        content = "SITE_ADDRESS=ghaf-binary-cache.northeurope.cloudapp.azure.com",
        "path"  = "/run/caddy.env"
      },
    ],
  })])

  allocate_public_ip = true
  subnet_id          = azurerm_subnet.binary_cache.id

  # Attach disk to the VM
  data_disks = [{
    name               = azurerm_managed_disk.binary_cache_caddy_state.name
    managed_disk_id    = azurerm_managed_disk.binary_cache_caddy_state.id
    virtual_machine_id = module.jenkins_controller_vm.virtual_machine_id
    lun                = "10"
    create_option      = "Attach"
    caching            = "None"
    disk_size_gb       = azurerm_managed_disk.binary_cache_caddy_state.disk_size_gb
  }]
}

resource "azurerm_subnet" "binary_cache" {
  name                 = "ghaf-infra-binary-cache"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.3.0/28"]
}

# Allow inbound HTTP(S)
resource "azurerm_network_interface_security_group_association" "binary_cache_vm" {
  network_interface_id      = module.binary_cache_vm.virtual_machine_network_interface_id
  network_security_group_id = azurerm_network_security_group.binary_cache_vm.id
}

resource "azurerm_network_security_group" "binary_cache_vm" {
  name                = "binary-cache-vm"
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location

  security_rule {
    name                       = "AllowSSHHTTPSInbound"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = [22, 443]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Allow the VM to read from the binary cache bucket
resource "azurerm_role_assignment" "binary_cache_access_storage" {
  scope                = azurerm_storage_container.binary_cache_1.resource_manager_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = module.binary_cache_vm.virtual_machine_identity_principal_id
}

# Create a data disk
resource "azurerm_managed_disk" "binary_cache_caddy_state" {
  name                 = "binary-cache-vm-caddy-state"
  resource_group_name  = azurerm_resource_group.default.name
  location             = azurerm_resource_group.default.location
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 1
}
