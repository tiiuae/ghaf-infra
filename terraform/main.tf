# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

provider "azurerm" {
  # https://github.com/hashicorp/terraform-provider-azurerm/issues/24804
  skip_provider_registration = true
  features {}
}

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Make sure this matches the version in ../nix/devshell.nix.
      # This will not pin the version (it's pinned in devshell.nix),
      # but makes terraform emit an error message in case the azurerm
      # version cached in local .terraform directory for one reason
      # or another does not match what is stated below.
      version = "=3.85.0"
    }
    secret = {
      source = "numtide/secret"
    }
  }
  # Backend for storing terraform state (see ../state-storage)
  backend "azurerm" {
    # resource_group_name and storage_account_name are set by the callee
    # from command line in terraform init, see terraform-init.sh
    container_name = "ghaf-infra-tfstate-container"
    key            = "ghaf-infra.tfstate"
  }
}

################################################################################

# Current signed-in user
data "azurerm_client_config" "current" {}

variable "envfile" {
  type        = string
  description = "Error out if .env-file is missing"
  default     = ".env"
  validation {
    condition     = fileexists(var.envfile)
    error_message = "ERROR: missing .env-file: (re-)run terraform-init.sh to initialize your environment"
  }
}

variable "convince" {
  type        = bool
  description = "Protect against accidental non-priv environment deployment"
  default     = false
}

# Use azure_region module to get the short name of the Azure region,
# see: https://registry.terraform.io/modules/claranet/regions/azurerm/latest
module "azure_region" {
  source       = "claranet/regions/azurerm"
  azure_region = data.azurerm_storage_account.tfstate.location
}

locals {
  # Raise an error if workspace is 'default',
  # this is a workaround to missing asserts in terraform:
  assert_workspace_not_default = regex(
    (terraform.workspace == "default") ?
  "((Force invalid regex pattern)\n\nERROR: workspace 'default' is not allowed" : "", "")

  envs = { for tuple in regexall("(.*)=(.*)", file(var.envfile)) : tuple[0] => tuple[1] }

  # Short name of the Azure region, see:
  # https://github.com/claranet/terraform-azurerm-regions/blob/master/REGIONS.md
  shortloc = module.azure_region.location_short

  # Sanitize workspace name
  ws = substr(replace(lower(terraform.workspace), "/[^a-z0-9]/", ""), 0, 16)

  ext_builder_machines = [
    "ssh://remote-build@build4.vedenemo.dev x86_64-linux /etc/secrets/remote-build-ssh-key 32 3 kvm,nixos-test,benchmark,big-parallel - -",
    "ssh://remote-build@hetzarm.vedenemo.dev aarch64-linux /etc/secrets/remote-build-ssh-key 40 3 kvm,nixos-test,benchmark,big-parallel - -"
  ]
  ext_builder_keyscan = ["build4.vedenemo.dev", "hetzarm.vedenemo.dev"]

  # We can not automatically assign alternative names per environment type
  # since we support having potentially many environments of the same type.
  # Otherwise we might end-up deploying, say, two 'dev' type instances
  # that both claim ownership of domain name 'dev-cache.vedenemo.dev'.
  # Such alternative names need to be manually configured for each instance
  # (once) in the relevant host's caddy config at /var/lib/caddy/caddy.env,
  # setting the SITE_ADDRESS accordingly.
  binary_cache_url        = "https://ghaf-binary-cache-${local.ws}.${azurerm_resource_group.infra.location}.cloudapp.azure.com"
  binary_cache_public_key = data.azurerm_key_vault_secret.binary_cache_signing_key_pub.value

  # Environment-specific configuration options.
  # See Azure vm sizes and specs at:
  # https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux
  # E.g. 'Standard_D2_v3' means: 2 vCPU, 8 GiB RAM
  opts = {
    priv = {
      persistent_id           = "priv"
      vm_size_binarycache     = "Standard_D2_v3"
      osdisk_size_binarycache = "50"
      vm_size_builder_x86     = "Standard_D2_v3"
      vm_size_builder_aarch64 = "Standard_D2ps_v5"
      osdisk_size_builder     = "150"
      vm_size_controller      = "Standard_E4_v5"
      osdisk_size_controller  = "150"
      num_builders_x86        = 0
      num_builders_aarch64    = 0
      ext_builder_machines    = local.ext_builder_machines
      ext_builder_keyscan     = local.ext_builder_keyscan
    }
    dev = {
      persistent_id           = "prod"
      vm_size_binarycache     = "Standard_D4_v3"
      osdisk_size_binarycache = "250"
      vm_size_builder_x86     = "Standard_D16_v3"
      vm_size_builder_aarch64 = "Standard_D8ps_v5"
      osdisk_size_builder     = "250"
      vm_size_controller      = "Standard_E4_v5"
      osdisk_size_controller  = "1000"
      num_builders_x86        = 0
      num_builders_aarch64    = 0
      ext_builder_machines    = local.ext_builder_machines
      ext_builder_keyscan     = local.ext_builder_keyscan
    }
    prod = {
      persistent_id           = "prod"
      vm_size_binarycache     = "Standard_D4_v3"
      osdisk_size_binarycache = "250"
      vm_size_builder_x86     = "Standard_D16_v3"
      vm_size_builder_aarch64 = "Standard_D8ps_v5"
      osdisk_size_builder     = "250"
      vm_size_controller      = "Standard_E4_v5"
      osdisk_size_controller  = "1000"
      num_builders_x86        = 0
      num_builders_aarch64    = 0
      ext_builder_machines    = local.ext_builder_machines
      ext_builder_keyscan     = local.ext_builder_keyscan
    }
    release = {
      persistent_id           = "release"
      vm_size_binarycache     = "Standard_D4_v3"
      osdisk_size_binarycache = "250"
      vm_size_builder_x86     = "Standard_D64_v3"
      vm_size_builder_aarch64 = "Standard_D64ps_v5"
      osdisk_size_builder     = "500"
      vm_size_controller      = "Standard_E16_v5"
      osdisk_size_controller  = "1000"
      num_builders_x86        = 1
      num_builders_aarch64    = 1
      ext_builder_machines    = []
      ext_builder_keyscan     = []
    }
  }

  # Read ssh-keys.yaml into local.ssh_keys
  ssh_keys = yamldecode(file("../ssh-keys.yaml"))

  # Determine the configuration options used in the ghaf-infra instance
  # based on the workspace name
  is_release = length(regexall("^release.*", local.ws)) > 0
  is_prod    = length(regexall("^prod.*", local.ws)) > 0
  is_dev     = length(regexall("^dev.*", local.ws)) > 0
  conf       = local.is_release ? "release" : local.is_prod ? "prod" : local.is_dev ? "dev" : "priv"

  # Protect against accidental non-priv environment deployment by requiring
  # variable -var="convince=true".
  assert_accidental_deployment = regex(
    ("${local.conf}" != "priv" && !(var.convince)) ?
  "((Force invalid regex pattern\n\nERROR: Deployment to non-priv requires variable 'convince'" : "", "")

  # Selects the persistent data for this ghaf-infra instance (see ./persistent)
  persistent_rg = local.envs["persistent_rg_name"]
  persistent_id = "id0${local.opts[local.conf].persistent_id}${local.shortloc}"

  # Selects builder ssh key
  use_ext_builders  = length(local.opts[local.conf].ext_builder_machines) > 0
  builder_sshkey_id = local.use_ext_builders ? "sshb-id0ext${local.shortloc}" : "sshb${local.ws}${local.shortloc}"
  builder_sshkey_rg = local.use_ext_builders ? local.persistent_rg : "ghaf-infra-${local.ws}"
}

################################################################################

# Resource group for this ghaf-infra instance
resource "azurerm_resource_group" "infra" {
  name     = "ghaf-infra-${local.ws}"
  location = data.azurerm_storage_account.tfstate.location
}

################################################################################

# Environment specific resources

# Virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "ghaf-infra-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.infra.location
  resource_group_name = azurerm_resource_group.infra.name
}

# Slice out a subnet for jenkins
resource "azurerm_subnet" "jenkins" {
  name                 = "ghaf-infra-jenkins"
  resource_group_name  = azurerm_resource_group.infra.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Slice out a subnet for the builders
resource "azurerm_subnet" "builders" {
  name                 = "ghaf-infra-builders"
  resource_group_name  = azurerm_resource_group.infra.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.4.0/28"]
}

# https://github.com/hashicorp/terraform-provider-azurerm/issues/15609
resource "random_string" "id" {
  length  = 8
  upper   = false
  special = false
}

# Storage account and storage container used to store VM images
resource "azurerm_storage_account" "vm_images" {
  name                            = "img${random_string.id.result}"
  resource_group_name             = azurerm_resource_group.infra.name
  location                        = azurerm_resource_group.infra.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
}

resource "azurerm_storage_container" "vm_images" {
  name                  = "ghaf-infra-vm-images"
  storage_account_name  = azurerm_storage_account.vm_images.name
  container_access_type = "private"
}

module "builder_ssh_key" {
  # Create ssh builder key if external builders are not used
  count  = (local.use_ext_builders) ? 0 : 1
  source = "./persistent/builder-ssh-key"
  # Must be globally unique, max 24 characters
  builder_ssh_keyvault_name = local.builder_sshkey_id
  resource_group_name       = azurerm_resource_group.infra.name
  location                  = azurerm_resource_group.infra.location
  tenant_id                 = data.azurerm_client_config.current.tenant_id
  object_id                 = data.azurerm_client_config.current.object_id
}

################################################################################

# Data sources to access terraform state, see ./state-storage

data "azurerm_storage_account" "tfstate" {
  name                = local.envs["storage_account_name"]
  resource_group_name = local.envs["storage_account_rg_name"]
}

################################################################################

# Data sources to access builder ssh key

# Builder ssh key
data "azurerm_key_vault" "ssh_remote_build" {
  name                = local.builder_sshkey_id
  resource_group_name = local.builder_sshkey_rg
  provider            = azurerm
  depends_on          = [module.builder_ssh_key]
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

################################################################################

# Data sources to access 'persistent' data
# see ./persistent and ./persistent/resources

# Binary cache storage
data "azurerm_storage_account" "binary_cache" {
  name                = "bches${local.persistent_id}"
  resource_group_name = local.persistent_rg
}

data "azurerm_storage_container" "binary_cache_1" {
  name                 = "binary-cache-v1"
  storage_account_name = data.azurerm_storage_account.binary_cache.name
}

# Binary cache signing key
data "azurerm_key_vault" "binary_cache_signing_key" {
  name                = "bchek-${local.persistent_id}"
  resource_group_name = local.persistent_rg
  provider            = azurerm
}

data "azurerm_key_vault_secret" "binary_cache_signing_key" {
  name         = "binary-cache-signing-key-priv"
  key_vault_id = data.azurerm_key_vault.binary_cache_signing_key.id
  provider     = azurerm
}

data "azurerm_key_vault_secret" "binary_cache_signing_key_pub" {
  name         = "binary-cache-signing-key-pub"
  key_vault_id = data.azurerm_key_vault.binary_cache_signing_key.id
  provider     = azurerm
}

# Reference the existing Key Vault
data "azurerm_key_vault" "ghaf_devenv_ca" {
  name                = "ghaf-devenv-ca"
  resource_group_name = "ghaf-devenev-pki"
}

# Data sources to access 'workspace-specific persistent' data
# see: ./persistent/workspace-specific

# Caddy state disk: binary cache
data "azurerm_managed_disk" "binary_cache_caddy_state" {
  name                = "binary-cache-vm-caddy-state-${local.ws}"
  resource_group_name = local.persistent_rg
}

# Caddy state disk: jenkins controller
data "azurerm_managed_disk" "jenkins_controller_caddy_state" {
  name                = "jenkins-controller-vm-caddy-state-${local.ws}"
  resource_group_name = local.persistent_rg
}

# Jenkins artifacts storage
data "azurerm_storage_account" "jenkins_artifacts" {
  name                = "artifact${local.ws}"
  resource_group_name = local.persistent_rg
}

data "azurerm_storage_container" "jenkins_artifacts_1" {
  name                 = "jenkins-artifacts-v1"
  storage_account_name = data.azurerm_storage_account.jenkins_artifacts.name
}

################################################################################
