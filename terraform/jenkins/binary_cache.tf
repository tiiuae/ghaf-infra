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
    # mount /dev/disk/by-lun/10 to /var/lib/caddy
    disk_setup = {
      "/dev/disk/by-lun/10" = {
        layout  = false # don't partition
        timeout = 60    # wait for device to appear
      }
    }
    fs_setup = [
      {
        filesystem = "ext4"
        partition  = "auto"
        device     = "/dev/disk/by-lun/10"
        label      = "caddy"
      }
    ]
    mounts = [
      ["/dev/disk/by-label/caddy", "/var/lib/caddy"]
    ]
    # TODO: this should be EnvironmentFile, so we don't need to restart
    write_files = [
      {
        content = "[Service]\nEnvironment=AZURE_STORAGE_ACCOUNT_NAME=ghafbinarycache",
        "path" = "/run/systemd/system/rclone-http.service.d/cloud-init.conf"
      },
      {
        content = "[Service]\nEnvironment=SITE_ADDRESS=ghaf-binary-cache.northeurope.cloudapp.azure.com",
        "path" = "/run/systemd/system/caddy.service.d/cloud-init.conf"
      },
    ],
    runcmd = [
      "systemctl daemon-reload", # pick up drop-ins
      "systemctl restart caddy.service",
      "systemctl restart rclone-http.service"
    ]
  })])

  subnet_id = azurerm_subnet.binary_cache.id
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

# Attach to the VM
resource "azurerm_virtual_machine_data_disk_attachment" "binary_cache_vm_caddy_state" {
  managed_disk_id    = azurerm_managed_disk.binary_cache_caddy_state.id
  virtual_machine_id = module.binary_cache_vm.virtual_machine_id
  lun                = "10"
  caching            = "None"
}
