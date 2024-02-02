# SPDX-FileCopyrightText: 2024 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

################################################################################

# May only contain alphanumeric characters and dashes and must be between 3-24
# chars, must be globally unique
variable "builder_ssh_keyvault_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tenant_id" {
  type = string
}

################################################################################

# Create a ED25519 key, which the jenkins master will use to authenticate with
# builders.
resource "tls_private_key" "ed25519_remote_build" {
  algorithm   = "ED25519"
  ecdsa_curve = "P521"
}

# Create an Azure key vault
resource "azurerm_key_vault" "ssh_remote_build" {
  name                = var.builder_ssh_keyvault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "standard"
  # The Azure Active Directory tenant ID that should be used for authenticating
  # requests to the key vault
  tenant_id = var.tenant_id
}

# Put the ed25519 private key used for ssh as a secret
resource "azurerm_key_vault_secret" "ssh_remote_build" {
  name         = "remote-build-ssh-private-key"
  value        = tls_private_key.ed25519_remote_build.private_key_openssh
  key_vault_id = azurerm_key_vault.ssh_remote_build.id

  # Each of the secrets needs an explicit dependency on the access policy.
  # Otherwise, Terraform may attempt to create the secret before creating the
  # access policy.
  # https://stackoverflow.com/a/74747333
  depends_on = [
    azurerm_key_vault_access_policy.ssh_remote_build_terraform
  ]
}

# Put the ed25519 public key used for ssh as a secret to make it accessible
# in builder configuration
resource "azurerm_key_vault_secret" "ssh_remote_build_pub" {
  name         = "remote-build-ssh-public-key"
  value        = tls_private_key.ed25519_remote_build.public_key_openssh
  key_vault_id = azurerm_key_vault.ssh_remote_build.id
  depends_on = [
    azurerm_key_vault_access_policy.ssh_remote_build_terraform
  ]
}

resource "azurerm_key_vault_access_policy" "ssh_remote_build_terraform" {
  key_vault_id = azurerm_key_vault.ssh_remote_build.id
  tenant_id    = var.tenant_id
  # "TerraformAdminsGHAFInfra" group
  object_id = "f80c2488-2301-4de8-89d6-4954b77f453e"

  secret_permissions = [
    "Get",
    "List",
    "Set"
  ]
}
