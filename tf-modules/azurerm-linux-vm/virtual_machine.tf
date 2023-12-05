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

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
}

resource "azurerm_network_security_group" "ssh_inbound" {
  name                = "${var.virtual_machine_name}-nsg-ssh-inbound"
  resource_group_name = var.resource_group_name
  location            = var.location
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
resource "azurerm_network_interface_security_group_association" "apply_ssh_inbound" {
  network_interface_id      = azurerm_network_interface.default.id
  network_security_group_id = azurerm_network_security_group.ssh_inbound.id
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
