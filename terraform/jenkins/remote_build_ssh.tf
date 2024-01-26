# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

# Reads the builder ssh key from a key vault
# on resource group "ghaf-infra-secrets" (see: ../azure-secrets)

data "azurerm_key_vault" "ssh_remote_build" {
  name                = "ghaf-ssh-remote-build"
  resource_group_name = "ghaf-infra-secrets"
  provider            = azurerm
}

data "azurerm_key_vault_secret" "ssh_remote_build" {
  name         = "remote-build-ssh-private-key"
  key_vault_id = data.azurerm_key_vault.ssh_remote_build.id
  provider     = azurerm
}

data "azurerm_key_vault_secret" "ssh_remote_build_pub" {
  name         = "remote-build-ssh-public-key"
  key_vault_id = data.azurerm_key_vault.ssh_remote_build.id
  provider     = azurerm
}
