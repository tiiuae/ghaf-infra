# SPDX-FileCopyrightText: 2024 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

# Reads the binary cache signing key from a key vault
# on resource group "ghaf-infra-secrets" (see: ../azure-secrets)

data "azurerm_key_vault" "binary_cache_signing_key" {
  name                = "ghaf-binarycache-signing"
  resource_group_name = "ghaf-infra-secrets"
  provider            = azurerm
}

data "azurerm_key_vault_secret" "binary_cache_signing_key" {
  name         = "binary-cache-signing-key"
  key_vault_id = data.azurerm_key_vault.binary_cache_signing_key.id
  provider     = azurerm
}
