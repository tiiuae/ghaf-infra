# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

# Storage account and storage container used to store VM images

resource "azurerm_storage_account" "vm_images" {
  name                            = "ghafinfravmimages"
  resource_group_name             = azurerm_resource_group.default.name
  location                        = azurerm_resource_group.default.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
}

resource "azurerm_storage_container" "vm_images" {
  name                  = "ghaf-infra-vm-images"
  storage_account_name  = azurerm_storage_account.vm_images.name
  container_access_type = "private"
}

