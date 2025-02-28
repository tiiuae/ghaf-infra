# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Build the Jenkins controller image
module "jenkins_controller_image" {
  source = "./modules/azurerm-nix-vm-image"

  nix_attrpath   = ""
  nix_entrypoint = "${path.module}/custom-nixos.nix"
  nix_argstr = {
    extraNixPublicKey = local.binary_cache_public_key
    systemName        = "az-jenkins-controller"
  }

  name                   = "jenkins-controller"
  resource_group_name    = azurerm_resource_group.infra.name
  location               = azurerm_resource_group.infra.location
  storage_account_name   = azurerm_storage_account.vm_images.name
  storage_container_name = azurerm_storage_container.vm_images.name
  depends_on             = [azurerm_storage_container.vm_images]
}

# Create a machine using this image
module "jenkins_controller_vm" {
  source = "./modules/azurerm-linux-vm"

  resource_group_name          = azurerm_resource_group.infra.name
  location                     = azurerm_resource_group.infra.location
  virtual_machine_name         = "ghaf-jenkins-controller-${local.ws}"
  virtual_machine_size         = local.opts[local.conf].vm_size_controller
  virtual_machine_osdisk_size  = local.opts[local.conf].osdisk_size_controller
  virtual_machine_source_image = module.jenkins_controller_image.image_id

  virtual_machine_custom_data = join("\n", ["#cloud-config", yamlencode({
    users = [
      for user in toset(["bmg", "flokli", "hrosten", "jrautiola", "cazfi", "vjuntunen", "ktu", "alextserepov", "fayad", "ctsopokis", "kanyfantakis"]) : {
        name                = user
        groups              = "wheel"
        ssh_authorized_keys = local.ssh_keys[user]
      }
    ]
    write_files = [
      # See corresponding EnvironmentFile= directives in services
      {
        content = "KEY_VAULT_NAME=${data.azurerm_key_vault.ssh_remote_build.name}\nSECRET_NAME=${data.azurerm_key_vault_secret.ssh_remote_build.name}",
        "path"  = "/var/lib/fetch-build-ssh-key/env"
      },
      {
        content = "KEY_VAULT_NAME=${data.azurerm_key_vault.binary_cache_signing_key.name}\nSECRET_NAME=${data.azurerm_key_vault_secret.binary_cache_signing_key.name}",
        "path"  = "/var/lib/fetch-binary-cache-signing-key/env"
      },
      {
        content = "AZURE_STORAGE_ACCOUNT_NAME=${data.azurerm_storage_account.binary_cache.name}",
        "path"  = "/var/lib/rclone-http/env"
      },
      {
        content = "AZURE_STORAGE_ACCOUNT_NAME=${data.azurerm_storage_account.jenkins_artifacts.name}",
        "path"  = "/var/lib/rclone-jenkins-artifacts/env"
      },
      # Render /etc/nix/machines with terraform. In the future, we might want to
      # autodiscover this, or better, have agents register with the controller,
      # rather than having to recreate the VM whenever the list of builders is
      # changed.
      {
        content = join("\n", concat(
          [for ip in toset(module.builder_vm[*].virtual_machine_ip_address) : "ssh://remote-build@${ip} x86_64-linux /etc/secrets/remote-build-ssh-key 16 1 kvm,nixos-test,benchmark,big-parallel - -"],
          [for ip in toset(module.arm_builder_vm[*].virtual_machine_ip_address) : "ssh://remote-build@${ip} aarch64-linux /etc/secrets/remote-build-ssh-key 16 1 kvm,nixos-test,benchmark,big-parallel - -"],
          local.opts[local.conf].ext_builder_machines,
        )),
        "path" = "/etc/nix/machines"
      },
      # Render /var/lib/builder-keyscan/scanlist, so known_hosts can be populated.
      {
        content = join("\n", toset(concat(
          module.builder_vm[*].virtual_machine_ip_address,
          module.arm_builder_vm[*].virtual_machine_ip_address,
          local.opts[local.conf].ext_builder_keyscan,
        ))),
        "path" = "/var/lib/builder-keyscan/scanlist"
      },
      {
        content = "SITE_ADDRESS=ghaf-jenkins-controller-${local.ws}.${azurerm_resource_group.infra.location}.cloudapp.azure.com",
        "path"  = "/var/lib/caddy/caddy.env"
      },
      # JENKINS_URL is read from this file by JCasC plugin
      # Configuration: hosts/azure/jenkins-controller/jenkins-casc.yaml
      # Value: jenkins: unclassified: location: url
      {
        content = "https://ghaf-jenkins-controller-${local.ws}.${azurerm_resource_group.infra.location}.cloudapp.azure.com",
        "path"  = "/var/lib/jenkins-casc/url"
      }
    ]
  })])

  allocate_public_ip    = true
  access_over_public_ip = true
  subnet_id             = azurerm_subnet.jenkins.id

  # Attach disk to the VM
  data_disks = [
    {
      name            = azurerm_managed_disk.jenkins_controller_jenkins_state.name
      managed_disk_id = azurerm_managed_disk.jenkins_controller_jenkins_state.id
      lun             = "10"
      # create_option = "Attach"
      caching      = "None"
      disk_size_gb = azurerm_managed_disk.jenkins_controller_jenkins_state.disk_size_gb
    },
    {
      name            = data.azurerm_managed_disk.jenkins_controller_caddy_state.name
      managed_disk_id = data.azurerm_managed_disk.jenkins_controller_caddy_state.id
      lun             = "11"
      create_option   = "Attach"
      caching         = "None"
      disk_size_gb    = data.azurerm_managed_disk.jenkins_controller_caddy_state.disk_size_gb
    }
  ]
}

resource "azurerm_network_interface_security_group_association" "jenkins_controller_vm" {
  network_interface_id      = module.jenkins_controller_vm.virtual_machine_network_interface_id
  network_security_group_id = azurerm_network_security_group.jenkins_controller_vm.id
}

resource "azurerm_network_security_group" "jenkins_controller_vm" {
  name                = "jenkins-controller-vm"
  resource_group_name = azurerm_resource_group.infra.name
  location            = azurerm_resource_group.infra.location

  security_rule {
    name                       = "AllowSSHHTTPSInbound"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = [22, 80, 443]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create a data disk
resource "azurerm_managed_disk" "jenkins_controller_jenkins_state" {
  name                 = "jenkins-controller-vm-jenkins-state"
  resource_group_name  = azurerm_resource_group.infra.name
  location             = azurerm_resource_group.infra.location
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 64
}

# Grant the VM read-only access to the Azure Key Vault Secret containing the
# ed25519 private key used to connect to remote builders.
resource "azurerm_key_vault_access_policy" "ssh_remote_build_jenkins_controller" {
  key_vault_id = data.azurerm_key_vault.ssh_remote_build.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = module.jenkins_controller_vm.virtual_machine_identity_principal_id

  secret_permissions = [
    "Get",
  ]
}

# Grant the Jenkins Controller VM's system-assigned managed identity access to the Key Vault
resource "azurerm_key_vault_access_policy" "jenkins_controller_kv_access" {
  key_vault_id = data.azurerm_key_vault.ghaf_devenv_ca.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = module.jenkins_controller_vm.virtual_machine_identity_principal_id

  key_permissions = [
    "Get",
    "List",
    "Sign",
    "Verify",
  ]

  certificate_permissions = [
    "Get",
    "List",
  ]
}


# Allow the VM to *write* to (and read from) the binary cache bucket
resource "azurerm_role_assignment" "jenkins_controller_access_storage" {
  scope                = data.azurerm_storage_container.binary_cache_1.resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.jenkins_controller_vm.virtual_machine_identity_principal_id
}

# Allow the VM to *write* to (and read from) the jenkins artifacts bucket
resource "azurerm_role_assignment" "jenkins_controller_access_artifacts" {
  scope                = data.azurerm_storage_container.jenkins_artifacts_1.resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.jenkins_controller_vm.virtual_machine_identity_principal_id
}


# Grant the VM read-only access to the Azure Key Vault Secret containing the
# binary cache signing key.
resource "azurerm_key_vault_access_policy" "binary_cache_signing_key_jenkins_controller" {
  key_vault_id = data.azurerm_key_vault.binary_cache_signing_key.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = module.jenkins_controller_vm.virtual_machine_identity_principal_id

  secret_permissions = [
    "Get",
  ]
}
