# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

resource "azurerm_resource_group" "default" {
  name     = "ghaf-infra-vedenemo"
  location = var.location
}


resource "azurerm_dns_zone" "main" {
  name                = "az.vedenemo.dev"
  resource_group_name = azurerm_resource_group.default.name
}
