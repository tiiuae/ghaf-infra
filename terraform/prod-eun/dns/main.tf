# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

locals {
  dns_suffix = "${replace(var.environment_name, "/^ghaf-infra-/", "")}.az.vedenemo.dev"
}

resource "azurerm_dns_zone" "main" {
  name                = local.dns_suffix
  resource_group_name = var.resource_group_name
}
