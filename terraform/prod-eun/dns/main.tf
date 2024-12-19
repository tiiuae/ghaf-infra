# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

variable "resource_group_name" {
  type = string
}

variable "environment_name" {
  type = string
}

locals {
  dns_suffix = "${replace(var.environment_name, "/^ghaf-infra-/", "")}.az.vedenemo.dev"
}

resource "azurerm_dns_zone" "main" {
  name                = local.dns_suffix
  resource_group_name = var.resource_group_name
}

resource "azurerm_dns_txt_record" "test" {
  name                = "test"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = var.resource_group_name
  ttl                 = 300

  record {
    value = "Success"
  }
}


output "name_servers" {
  value = azurerm_dns_zone.main.name_servers
}
