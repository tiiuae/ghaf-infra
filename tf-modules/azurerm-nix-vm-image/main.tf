# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

resource "azurerm_storage_blob" "default" {
  name                   = "${var.name}.vhd"
  storage_account_name   = var.storage_account_name
  storage_container_name = var.storage_container_name
  type                   = "Page" # necessary to be able to create an image out of it
  source                 = "${data.external.nix_build.result.outPath}/disk.vhd"
}

data "external" "nix_build" {
  program = ["${path.module}/nix-build.sh"]

  query = {
    attrpath   = var.nix_attrpath
    entrypoint = var.nix_entrypoint
  }
}

resource "azurerm_image" "default" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_disk {
    blob_uri = azurerm_storage_blob.default.url
    os_state = "Generalized"
    os_type  = "Linux"
  }
}

output "image_id" {
  value = azurerm_image.default.id
}
