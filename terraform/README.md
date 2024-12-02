<!--
SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Ghaf-infra: Terraform

This directory contains the root terraform module describing the [ghaf](https://github.com/tiiuae/ghaf) CI setup in Azure.

For architectural description, see [README-azure.md](./README-azure.md) originally from [PR#35](https://github.com/tiiuae/ghaf-infra/pull/35)

> The setup uses Nix to build disk images, uploads them to Azure, and then boots
> virtual machines off of them.
>
> Images are considered "appliance images", meant the Nix code describing their
> configuration describes the exact same purpose of the machine (no two-staged
> deployment process, the machine does the thing it's supposed to do after
> bootup), allowing to remove the need for e.g. ssh access as much as possible.
>
> Machines are considered ephemeral, every change in the appliance image / nixos
> configuration causes a new image to be built, and a new VM to be booted with
> that new image.

## Getting Started

This document assumes you have [`nix`](https://nixos.org/download.html) package manager installed on you local host.
Experimental feature "nix-command" must be enabled.

Clone this repository:
```bash
❯ git clone https://github.com/tiiuae/ghaf-infra.git
❯ cd ghaf-infra
```

Bootstrap nix-shell with the required dependencies:
```bash
# Start a nix-shell with required dependencies:
❯ nix-shell

# Authenticate with az login:
❯ az login

# Terraform comands are executed under the terraform directory:
❯ cd terraform/
```

All commands in this document are executed from nix-shell inside the `terraform` directory.

## Directory Structure
```
terraform
├── persistent
│   ├── binary-cache-sigkey
│   ├── binary-cache-storage
│   ├── builder-ssh-key
│   ├── resources
│   └── workspace-specific
├── state-storage
│   └── tfstate-storage.tf
├── modules
│   ├── arm-builder-vm
│   ├── azurerm-linux-vm
│   └── azurerm-nix-vm-image
├── binary-cache.tf
├── builder.tf
├── jenkins-controller.tf
└── main.tf
```
- The `terraform` directory contains the root terraform deployment files with the VM configurations `binary-cache.tf`, `builder.tf`, and `jenkins-controller.tf` matching the components described in [README-azure.md](./README-azure.md) in its [components section](./README-azure.md#components).
- The `terraform/persistent` directory contains the terraform configuration for parts of the infrastructure that are considered persistent - resources defined under `terraform/persistent` will not be removed even if the ghaf-infra instance is otherwise removed. An example of such persistent ghaf-infra resource is the binary cache storage as well as the binary cache signing key. There may be many 'persistent' infrastructure instances - currently `priv` `dev/prod` and `release` deployments have their own instances of the persistent resources. Section [Multiple Environments with Terraform Workspaces](./README.md#multiple-environments-with-terraform-workspaces) discusses this topic with more details.
- The `terraform/state-storage` directory contains the terraform configuration for the ghaf-infra remote backend state storage using Azure storage blob. See section [Initializing Azure State and Persistent Data](./README.md#initializing-azure-state-and-persistent-data) for more details.
- The `terraform/modules` directory contains terraform modules used from the ghaf-infra VM configurations to build, upload, and spin up Azure nix images.

## Initializing Ghaf-infra Environment
```bash
# Inside the terraform directory
# Replace 'workspacename' with the name of the workspace you are going to work with
❯ ./terraform-init.sh -w workspacename
[+] Initializing state storage
[+] Initializing persistent data
...
[+] Running terraform init
```
`terraform-init.sh` will not do anything if the initialization has already been done. In other words, it's safe to run the script many times; it will not destroy or re-initialize anything if the init was already executed.

## Multiple Environments with Terraform Workspaces

To support infrastructure development in isolated environments, this project uses [terraform workspaces](https://developer.hashicorp.com/terraform/cli/workspaces).
The main reasons for using terraform workspaces include:
- Different workspaces allow deploying different instances of ghaf-infra. Each instance has a completely separate state data, making it possible to deploy `dev`, `prod`, `release` or even private development instances of ghaf-infra. This makes it possible to first develop and test infrastructure changes in a private development environment, before proposing changes to shared (e.g. `dev` or `prod`) environments. The configuration codebase is the same between all the environments, with the differentiation options defined in the [`main.tf`](./main.tf#L105).
- Parts of the ghaf-infra infrastructure are persistent and shared between different environments. As an example, private environments share the binary cache storage. This arrangement makes it possible to treat, for instance, private ghaf-infra instances dispensable: ghaf-infra instances can be temporary and short-lived as it's easy to spin-up new environments without losing any valuable data. The persistent data is configured outside the root ghaf-infra terraform deployment in the `terraform/persistent` directory. There may be many 'persistent' infrastructure instances - currently `priv`, `dev/prod` and `release` deployments have their own instances of the persistent resources. This means that `priv`, `dev/prod` and `release` instances of ghaf-infra do **not** share any persistent data. As an example, `priv` and `prod` deployments of ghaf-infra have a separate binary cache storage. The binding to persistent resources from ghaf-infra is done in the [`main.tf`](./main.tf) based on the terraform workspace name and resource location. Persistent data initialization is automatically done with `terraform-init.sh` script.

To help facilitate the usage of terraform workspaces in setting-up distinct copies of ghaf-infra, one can [use terraform workspaces from the command line](https://developer.hashicorp.com/terraform/cli/workspaces#managing-cli-workspaces). Below, for the sake of example, we setup a private deployment instance of ghaf-infra:

```bash
# Activate private development environment 'henri'
❯ ./terraform-init.sh -w henri
[+] Using state 'ghaf-infra-0-state-eun'
[+] Using persistent 'ghaf-infra-0-persistent-eun'
[+] Initializing workspace-specific persistent
[+] Initializing workspace
[+] Listing workspaces:
  default
  dev0
* henri       # <-- indicates active workspace
  prod
  release
```

## Terraform workflow

Following describes the intended workflow, with commands executed from the nix-shell.

Once your are ready to deploy your terraform or nix configuration changes, the following sequence of commands typically take place:
```bash
# Inside the terraform directory

# Format the terraform code files:
❯ terraform fmt -recursive

# Validate the terraform changes:
❯ terraform validate

# Make sure you deploy to the correct ghaf-infra instance.
# Use terraform workspace select <workspace_name> to switch workspaces
❯ terraform workspace list
  default
  dev0
* henri       # <-- This example deploys to private dev environment
  prod
  release

# Show what actions terraform would take on apply:
❯ terraform plan

# Apply your configuration changes:
❯ terraform apply
```

Once `terraform apply` completes, the private development infrastructure is deployed.
You can now play around in your isolated copy of the infrastructure, testing and updating the changes, making sure the changes work as expected before merging the changes.

## Destroying Ghaf-infra Environment
Once you no longer need your playground environment, the private development environment can be destroyed:
```bash
# Inside the terraform directory

❯ terraform workspace list
  default
  dev0
* henri
  prod
  release

❯ terraform workspace select henri
❯ terraform apply -destroy
```
The above command(s) remove all the resources that were created for the given environment.

## Common Terraform Errors

Below are some common Terraform errors with tips on how to resolve each.

#### Error: A resource with the ID <ID> already exists
```bash
❯ terraform apply
...
azurerm_virtual_machine_extension.deploy_ubuntu_builder: Creating...
╷
│ Error: A resource with the ID "/subscriptions/<SUBID>/resourceGroups/rg-name-here/providers/Microsoft.Compute/virtualMachines/testvm/extensions/testvm-vmext" already exists - to be managed via Terraform this resource needs to be imported into the State. Please see the resource documentation for "azurerm_virtual_machine_extension" for more information.
```

Example fix:
```bash
❯ terraform import azurerm_virtual_machine_extension.deploy_ubuntu_builder /subscriptions/<SUBID>/resourceGroups/rg-name-here/providers/Microsoft.Compute/virtualMachines/testvm/extensions/testvm-vmext

# Ref: https://stackoverflow.com/questions/61418168/terraform-resource-with-the-id-already-exists
```

#### Error: Backend configuration changed
```bash
❯ ./terraform-init.sh -w workspacename
[+] Using state 'ghaf-infra-state-0-eun'
[+] Using persistent 'ghaf-infra-persistent-0-eun'
[+] Initializing workspace-specific persistent
╷
│ Error: Backend configuration changed
│
│ A change in the backend configuration has been detected, which may require migrating existing state.
│
│ If you wish to attempt automatic migration of the state, use "terraform init -migrate-state".
│ If you wish to store the current configuration with no changes to the state, use "terraform init -reconfigure".
```

Above error (or similar) is caused by changed terraform backend state.
Fix the local state reference by removing local state files and re-running `terraform-init.sh`:

```bash
# Make sure you don't have any untracked files you want to keep in your working tree
# before running the below command
❯ git clean -ffdx
# Replace 'workspacename' with the name of the workspace you'll work with
❯ ./terraform-init.sh -w workspacename
```

#### Error: creating/updating Image
```bash
❯ terraform apply -auto-approve
...
│ Error: creating/updating Image (Subscription: "<SUBID>"
│ Resource Group Name: "ghaf-infra-henri"
│ Image Name: "binary-cache"): performing CreateOrUpdate: unexpected status 400 (400 Bad Request) with error: InvalidParameter: The source blob https://imghenrieun.blob.core.windows.net/ghaf-infra-vm-images/binary-cache.vhd is not accessible.
│
│   with module.binary_cache_image.azurerm_image.default,
│   on modules/azurerm-nix-vm-image/main.tf line 32, in resource "azurerm_image" "default":
│   32: resource "azurerm_image" "default" {
```

Above error (or similar) is likely caused by a bug in terraform azurerm provider: it appears it tries to use the uploaded vhd image too soon after upload, while it's still not fully available. It frequently occurs on deploying a clean (previously undeployed) ghaf-infra environment. Fix the issue by running terraform apply again:

```bash
❯ terraform apply -auto-approve
```
