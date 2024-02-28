# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

################################################################################

# May only contain alphanumeric characters and dashes and must be between 3-24
# chars, must be globally unique
variable "bincache_keyvault_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "secret_resource" {
  type = object({
    value = string
  })
}

variable "tenant_id" {
  type = string
}


################################################################################

# Create an Azure key vault.
resource "azurerm_key_vault" "binary_cache_signing_key" {
  name                = var.bincache_keyvault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "standard"
  #  The Azure Active Directory tenant ID that should be used for authenticating
  # requests to the key vault.
  tenant_id = var.tenant_id
}

# Upload the binary cache signing key as a vault secret
resource "azurerm_key_vault_secret" "binary_cache_signing_key" {
  name         = "binary-cache-signing-key-priv"
  value        = var.secret_resource.value
  key_vault_id = azurerm_key_vault.binary_cache_signing_key.id

  # Each of the secrets needs an explicit dependency on the access policy.
  # Otherwise, Terraform may attempt to create the secret before creating the
  # access policy.
  # https://stackoverflow.com/a/74747333
  depends_on = [
    azurerm_key_vault_access_policy.binary_cache_signing_key_terraform
  ]
}

resource "azurerm_key_vault_access_policy" "binary_cache_signing_key_terraform" {
  key_vault_id = azurerm_key_vault.binary_cache_signing_key.id
  tenant_id    = var.tenant_id
  # "TerraformAdminsGHAFInfra" group
  object_id = "f80c2488-2301-4de8-89d6-4954b77f453e"

  secret_permissions = [
    "Get",
    "List",
    "Set"
  ]
}

