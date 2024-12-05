# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

resource "azurerm_storage_blob" "default" {
  name                   = "${var.name}.vhd"
  storage_account_name   = var.storage_account_name
  storage_container_name = var.storage_container_name
  type                   = "Page" # necessary to be able to create an image out of it
  source                 = "${data.external.nix_build.result.outPath}/disk.vhd"
  timeouts {
    create = "1h"
    update = "1h"
    read   = "1h"
    delete = "1h"
  }
}

data "external" "nix_build" {
  program = ["${path.module}/nix-eval.sh"]

  query = {
    argstr_json = jsonencode({
      # filter out null values and empty strings before rendering argstr_json.
      for k, v in var.nix_argstr : k => v if v != null && v != ""
    })
    attrpath   = var.nix_attrpath
    entrypoint = var.nix_entrypoint
    build      = "true"
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
  depends_on = [
    azurerm_storage_blob.default,
    data.external.nix_build
  ]
}

output "image_id" {
  value = azurerm_image.default.id
}
