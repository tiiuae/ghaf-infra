# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

output "resource_group_name" {
  value = azurerm_resource_group.ghaf_infra_tf_dev.name
}

output "resource_group_location" {
  value = var.resource_group_location
}
