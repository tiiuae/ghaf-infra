# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0


# Grant the Jenkins Controller VM's system-assigned managed identity access to the Key Vault
# resource "azurerm_key_vault_access_policy" "jenkins_controller_kv_access" {
#  key_vault_id = data.azurerm_key_vault.ghaf_prodenv_ca.id
#  tenant_id    = data.azurerm_client_config.current.tenant_id
#  object_id    = module.jenkins_controller_vm.virtual_machine_identity_principal_id

# key_permissions = [
#    "Get",
#    "List",
#    "Sign",
#    "Verify",
#  ]

#  certificate_permissions = [
#    "Get",
#    "List",
#  ]
#}

# Create signing keyvault for comms team within the workspace resource group.
resource "azurerm_key_vault" "sigkv1" {
  name                = "ghaf-sig-kv-comms-dev"
  location            = azurerm_resource_group.pki.location
  resource_group_name = "ghaf-infra-devuaen-pki"
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Access policy for the authenticated user
  # Needed for self-signed certificate creation
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
      "List",
      "Sign",
      "Verify",
      "Delete",
      "Purge"
    ]

    secret_permissions = [
      "Get",
      "List",
      "Delete",
      "Purge"
    ]
    certificate_permissions = [
      "Get",
      "List",
      "Create",
      "Delete",
      "Purge"
    ]
  }

  # Access policy for Jenkins Controller VM.
}

# Create a self-signed certificate for image signing
resource "azurerm_key_vault_certificate" "imgcert1" {
  name         = "INT-Ghaf-Devuaen-Image"
  key_vault_id = azurerm_key_vault.sigkv1.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_type   = "EC"
      key_size   = 256
      curve      = "P-256"
      reuse_key  = false
    }

    x509_certificate_properties {
      subject            = "CN=Ghaf-devuaen-cert-img"
      validity_in_months = 12
      key_usage = [
        "digitalSignature",
        "keyAgreement"
      ]
    }

    secret_properties {
      content_type = "application/x-pem-file"
    }
  }
}

# Create a self-signed certificate for provenance signing
resource "azurerm_key_vault_certificate" "provcert1" {
  name         = "INT-Ghaf-Devuaen-Provenance"
  key_vault_id = azurerm_key_vault.sigkv1.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_type   = "EC"
      key_size   = 256
      curve      = "P-256"
      reuse_key  = false
    }

    x509_certificate_properties {
      subject            = "CN=Ghaf-devuaen-cert-prov"
      validity_in_months = 12
      key_usage = [
        "digitalSignature",
        "keyAgreement"
      ]
    }

    secret_properties {
      content_type = "application/x-pem-file"
    }
  }
}

# Create signing keyvault for fog team within the workspace resource group.
resource "azurerm_key_vault" "sigkv2" {
  name                = "ghaf-sig-kv-fog-dev"
  location            = azurerm_resource_group.pki.location
  resource_group_name = "ghaf-infra-devuaen-pki"
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Access policy for the authenticated user
  # Needed for self-signed certificate creation
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
      "List",
      "Sign",
      "Verify",
      "Delete",
      "Purge"
    ]

    secret_permissions = [
      "Get",
      "List",
      "Delete",
      "Purge"
    ]
    certificate_permissions = [
      "Get",
      "List",
      "Create",
      "Delete",
      "Purge"
    ]
  }
}

# Create a self-signed certificate for image signing
resource "azurerm_key_vault_certificate" "imgcert2" {
  name         = "INT-Ghaf-Devuaen-Image"
  key_vault_id = azurerm_key_vault.sigkv2.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_type   = "EC"
      key_size   = 256
      curve      = "P-256"
      reuse_key  = false
    }

    x509_certificate_properties {
      subject            = "CN=Ghaf-devuaen-cert-img"
      validity_in_months = 12
      key_usage = [
        "digitalSignature",
        "keyAgreement"
      ]
    }

    secret_properties {
      content_type = "application/x-pem-file"
    }
  }
}

# Create a self-signed certificate for provenance signing
resource "azurerm_key_vault_certificate" "provcert2" {
  name         = "INT-Ghaf-Devuaen-Provenance"
  key_vault_id = azurerm_key_vault.sigkv2.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_type   = "EC"
      key_size   = 256
      curve      = "P-256"
      reuse_key  = false
    }

    x509_certificate_properties {
      subject            = "CN=Ghaf-devuaen-cert-prov"
      validity_in_months = 12
      key_usage = [
        "digitalSignature",
        "keyAgreement"
      ]
    }

    secret_properties {
      content_type = "application/x-pem-file"
    }
  }
}
