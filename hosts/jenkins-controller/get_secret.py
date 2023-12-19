"""
This script retrieves a secret specified in $SECRET_NAME
from an Azure Key Vault in $KEY_VAULT_NAME
and prints it to stdout.

It uses the default Azure credential client.
"""

from azure.keyvault.secrets import SecretClient
from azure.identity import DefaultAzureCredential

import os

key_vault_name = os.environ["KEY_VAULT_NAME"]
secret_name = os.environ["SECRET_NAME"]

credential = DefaultAzureCredential()
client = SecretClient(
    vault_url=f"https://{key_vault_name}.vault.azure.net",
    credential=credential
)

s = client.get_secret(secret_name)
print(s.value)
