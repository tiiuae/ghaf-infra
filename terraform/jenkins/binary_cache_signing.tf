# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

# nix-store --generate-binary-cache-key foo secret-key public-key
# terraform import secret_resource.binary_cache_signing_key "$(< ./secret-key)"
resource "secret_resource" "binary_cache_signing_key" {
  lifecycle {
    # To support automatically generating and destroying temp signing keys
    # with playground/terraform-az-dev.sh, `prevent_destroy` needs to be set
    # to `false`:
    prevent_destroy = false
  }
}

# Create an Azure key vault.
resource "azurerm_key_vault" "binary_cache_signing_key" {
  # this must be globally unique
  name                = "sig-${local.name_postfix}"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  sku_name            = "standard"
  #  The Azure Active Directory tenant ID that should be used for authenticating
  # requests to the key vault.
  tenant_id = data.azurerm_client_config.current.tenant_id
}

# Upload the binary cache signing key as a vault secret
resource "azurerm_key_vault_secret" "binary_cache_signing_key" {
  name         = "binary-cache-signing-key"
  value        = secret_resource.binary_cache_signing_key.value
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
  tenant_id    = data.azurerm_client_config.current.tenant_id
  # "TerraformAdminsGHAFInfra" group
  object_id = "f80c2488-2301-4de8-89d6-4954b77f453e"

  secret_permissions = [
    "Get",
    "List",
    "Set"
  ]
}
