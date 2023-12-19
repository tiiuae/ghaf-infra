# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

# Create the storage account and storage container
resource "azurerm_storage_account" "binary_cache" {
  name                            = "ghafbinarycache"
  resource_group_name             = azurerm_resource_group.default.name # TODO: separate resource group?
  location                        = azurerm_resource_group.default.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
}

resource "azurerm_storage_container" "binary_cache_1" {
  name                  = "binary-cache-v1"
  storage_account_name  = azurerm_storage_account.binary_cache.name
  container_access_type = "private"
}

# Create a file inside the nar/ subdir.
# It seems rclone doesn't create the parent directory and fails to upload the
# first NAR otherwise.
resource "azurerm_storage_blob" "nar_keep" {
  name                   = "nar/.keep"
  storage_account_name   = azurerm_storage_account.binary_cache.name
  storage_container_name = azurerm_storage_container.binary_cache_1.name
  type                   = "Block"
  source_content         = ""
}
