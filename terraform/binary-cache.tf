# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

module "binary_cache_image" {
  source = "./modules/azurerm-nix-vm-image"

  nix_attrpath   = ""
  nix_entrypoint = "${path.module}/custom-nixos.nix"
  nix_argstr = {
    extraNixPublicKey = local.binary_cache_public_key
    systemName        = "az-binary-cache"
  }

  name                   = "binary-cache"
  resource_group_name    = azurerm_resource_group.infra.name
  location               = azurerm_resource_group.infra.location
  storage_account_name   = azurerm_storage_account.vm_images.name
  storage_container_name = azurerm_storage_container.vm_images.name
  depends_on             = [azurerm_storage_container.vm_images]
}

module "binary_cache_vm" {
  source = "./modules/azurerm-linux-vm"

  resource_group_name          = azurerm_resource_group.infra.name
  location                     = azurerm_resource_group.infra.location
  virtual_machine_name         = "ghaf-binary-cache-${local.ws}"
  virtual_machine_size         = local.opts[local.conf].vm_size_binarycache
  virtual_machine_osdisk_size  = local.opts[local.conf].osdisk_size_binarycache
  virtual_machine_source_image = module.binary_cache_image.image_id

  virtual_machine_custom_data = join("\n", ["#cloud-config", yamlencode({
    users = [
      for user in toset(["bmg", "flokli", "hrosten", "jrautiola", "vjuntunen", "cazfi", "fayad", "kanyfantakis", "ctsopokis"]) : {
        name                = user
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        ssh_authorized_keys = local.ssh_keys[user]
      }
    ]
    # See corresponding EnvironmentFile= directives in services
    write_files = [
      {
        content = "AZURE_STORAGE_ACCOUNT_NAME=${data.azurerm_storage_account.binary_cache.name}",
        "path"  = "/var/lib/azure-nix-cache-proxy/env"
      },
      {
        content = "SITE_ADDRESS=${local.binary_cache_url}"
        "path"  = "/var/lib/caddy/caddy.env"
      },
    ],
  })])

  allocate_public_ip = true
  subnet_id          = azurerm_subnet.binary_cache.id

  # Attach disk to the VM
  data_disks = [{
    name            = data.azurerm_managed_disk.binary_cache_caddy_state.name
    managed_disk_id = data.azurerm_managed_disk.binary_cache_caddy_state.id
    lun             = "10"
    create_option   = "Attach"
    caching         = "None"
    disk_size_gb    = data.azurerm_managed_disk.binary_cache_caddy_state.disk_size_gb
  }]
}

resource "azurerm_subnet" "binary_cache" {
  name                 = "ghaf-infra-binary-cache"
  resource_group_name  = azurerm_resource_group.infra.name
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
  resource_group_name = azurerm_resource_group.infra.name
  location            = azurerm_resource_group.infra.location

  security_rule {
    name                       = "AllowSSHHTTPSInbound"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = [22, 80, 443]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Allow the VM to read from the binary cache bucket
resource "azurerm_role_assignment" "binary_cache_access_storage" {
  scope                = data.azurerm_storage_container.binary_cache_1.resource_manager_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = module.binary_cache_vm.virtual_machine_identity_principal_id
}
