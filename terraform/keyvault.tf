# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

variable "signing_key_vault_name" {
  default = "ghaf-keyvault-${local.ws}"
}

data "azurerm_key_vault" "target_kv" {
  name                = var.signing_key_vault_name
  resource_group_name = var.resource_group_name
}

variable "cert_image_name" {
  default = "INT-Ghaf-Devenv-Image"
}

variable "cert_provenance_name" {
  default = "INT-Ghaf-Devenv-Provenance"
}

resource "azurerm_key_vault" "kv" {
  name                = var.signing_key_vault_name
  location            = azurerm_resource_group.infra.location
  resource_group_name = azurerm_resource_group.infra.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Only create if not found
  # count = data.azurerm_key_vault.existing_kv.id == null ? 1 : 0
}

resource "azurerm_key_vault_certificate" "cert1" {
  name         = var.certificate_image_name
  key_vault_id = azurerm_key_vault.target_kv.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_type   = "EC"
      key_size   = 256
      reuse_key  = false
    }

    x509_certificate_properties {
      subject            = "CN=example-cert1"
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

  # Only create if Key Vault is created
  # count = length(azurerm_key_vault.kv) > 0 ? 1 : 0
}

resource "azurerm_key_vault_certificate" "cert2" {
  name         = var.certificate_provenance_name
  key_vault_id = azurerm_key_vault.target_kv.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_type   = "EC"
      key_size   = 256
      reuse_key  = false
    }

    x509_certificate_properties {
      subject            = "CN=example-cert2"
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

  # Only create if Key Vault is created
  # count = length(azurerm_key_vault.kv) > 0 ? 1 : 0
}
