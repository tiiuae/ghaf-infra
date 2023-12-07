# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

resource "azurerm_linux_virtual_machine" "main" {
  name                = var.virtual_machine_name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.virtual_machine_size

  # Unused, but required by the API. May not be root either
  admin_username = "foo"
  admin_password = "S00persecret"

  # We *don't* support password auth, and this doesn't change anything.
  # However, if we don't set this to false we need to
  # specify additional pubkeys.
  disable_password_authentication = false
  # We can't use admin_ssh_key, as it only works for the admin_username.

  network_interface_ids = [azurerm_network_interface.default.id]
  source_image_id       = var.virtual_machine_source_image

  identity {
    type = "SystemAssigned"
  }

  # We only set custom_data here, not user_data.
  # user_data is more recent, and allows updates without recreating the machine,
  # but at least cloud-init 23.1.2 blocks boot if custom_data is not set.
  # (It logs about not being able to mount /dev/sr0 to /metadata).
  # This can be worked around by setting custom_data to a static placeholder,
  # but user_data is still ignored.
  # TODO: check this again with a more recent cloud-init version.
  custom_data = (var.virtual_machine_custom_data == "") ? null : base64encode(var.virtual_machine_custom_data)

  # Enable boot diagnostics, use the managed storage account to store them
  boot_diagnostics {
    storage_account_uri = null
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
}

resource "azurerm_network_interface" "default" {
  name                = "${var.virtual_machine_name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.default.id
  }
}

resource "azurerm_public_ip" "default" {
  name                = "${var.virtual_machine_name}-pub-ip"
  domain_name_label   = var.virtual_machine_name
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
}

output "virtual_machine_id" {
  value = azurerm_linux_virtual_machine.main.id
}

output "virtual_machine_identity_principal_id" {
  value = azurerm_linux_virtual_machine.main.identity[0].principal_id
}

output "virtual_machine_network_interface_id" {
  value = azurerm_network_interface.default.id
}
