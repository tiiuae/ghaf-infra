# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

variable "ns_delegations" {
  type        = map(list(string))
  description = <<EOF
    Map from environment shortcode to NS records pointing to a nameserver
    serving a $shortcode.az.vedenemo.dev DNS Zone
  EOF
}

variable "location" {
  type = string
}

resource "azurerm_resource_group" "default" {
  name     = "ghaf-infra-vedenemo"
  location = var.location
}


resource "azurerm_dns_zone" "main" {
  name                = "az.vedenemo.dev"
  resource_group_name = azurerm_resource_group.default.name
}

resource "azurerm_dns_ns_record" "ns_delegations" {
  for_each = var.ns_delegations

  name                = each.key
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = azurerm_resource_group.default.name
  ttl                 = 300

  records = each.value
}
