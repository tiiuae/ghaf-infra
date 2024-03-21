# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

resource "azurerm_storage_blob" "default" {
  name                   = "${var.name}.vhd"
  storage_account_name   = var.storage_account_name
  storage_container_name = var.storage_container_name
  type                   = "Page" # necessary to be able to create an image out of it
  source                 = "${data.external.nix_build.result.outPath}/disk.vhd"
}

data "external" "nix_build" {
  program = ["${path.module}/nix-eval.sh"]

  query = {
    argstr_json = jsonencode(var.nix_argstr)
    attrpath    = var.nix_attrpath
    entrypoint  = var.nix_entrypoint
    build       = "true"
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
