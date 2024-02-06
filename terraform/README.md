<!--
SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)

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

Clone this repository:
```bash
$ git clone https://github.com/tiiuae/ghaf-infra.git
$ cd ghaf-infra
```

Bootstrap nix-shell with the required dependencies:
```bash
# Start a nix-shell with required dependencies:
$ nix-shell

# Authenticate with az login:
$ az login

# Terraform comands are executed under the terraform directory:
$ cd terraform/
```

All commands in this document are executed from nix-shell inside the `terraform` directory.

## Directory Structure
```
terraform
├── azarm
├── persistent
│   ├── binary-cache-sigkey
│   ├── binary-cache-storage
│   ├── builder-ssh-key
├── playground
│   ├── terraform-playground.sh
├── state-storage
│   └── tfstate-storage.tf
├── modules
│   ├── azurerm-linux-vm
│   └── azurerm-nix-vm-image
├── binary-cache.tf
├── builder.tf
├── jenkins-controller.tf
└── main.tf
```
- The `terraform` directory contains the root terraform deployment files with the VM configurations `binary-cache.tf`, `builder.tf`, and `jenkins-controller.tf` matching the components described in [README-azure.md](./README-azure.md) in its [components section](./README-azure.md#components).
- The `terraform/azarm` directory contains the terraform configuration for Azure `aarch64` builder which is used from ghaf github-actions [build.yml workflow](https://github.com/tiiuae/ghaf/blob/e81ccfb41d75eda0488b6b4325aeccb8385ce960/.github/workflows/build.yml#L151) to build `aarch64` targets for authorized PRs pre-merge. `azarm` is disconnected from the root terraform module: it's a separate configuration with its own state.
- The `terraform/persistent` directory contains the terraform configuration for parts of the infrastructure that are shared between the ghaf-infra development instances. An example of such persistent ghaf-infra resource is the binary cache storage as well as the binary cache signing key. There may be many 'persistent' infrastructure instances - currently `dev` and `prod` deployments have their own instances of the persistent resources. Section [Multiple Environments with Terraform Workspaces](./README.md#multiple-environments-with-terraform-workspaces) discusses this topic with more details.
- The `terraform/playground` directory contains tooling to facilitate the usage of terraform workspaces in setting-up distinct copies of the ghaf-infra infrastructure, i.e. 'playground' `dev` environments. It also includes an [example test infrastructure](./playground/test-infra.tf) that allows deploying example infrastructure including just one nix VM, highlighting the use of `terraform/modules` to build and upload the nix image on Azure.
- The `terraform/state-storage` directory contains the terraform configuration for the ghaf-infra remote backend state storage using Azure storage blob. See section [Initializing Azure State and Persistent Data](./README.md#initializing-azure-state-and-persistent-data) for more details.
- The `terraform/modules` directory contains terraform modules used from the ghaf-infra VM configurations to build, upload, and spin up Azure nix images.

## Initializing Azure State and Persistent Data
This project stores the terraform state in a remote storage in an azure storage blob as configured in [tfstate-storage.tf](./state-storage/tfstate-storage.tf). The benefits of using such remote storage setup are well outlined in [storing state in azure storage](https://learn.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage) and [terraform backend configuration](https://developer.hashicorp.com/terraform/language/settings/backends/configuration).

To initialize the backend storage, use the `terraform-init-sh`:

```bash
# Inside the terraform directory
$ ./terraform-init.sh 
[+] Initializing state storage
[+] Initializing persistent data
...
[+] Running terraform init
```
`terraform-init.sh` will not do anything if the initialization has already been done. In other words, it's safe to run the script many times; it will not destroy or re-initialize anything if the init was already executed.

In addition to the shared terraform state, some of the infrastructure resources are also shared between the ghaf-infra instances. `terraform-init.sh` initializes the persistent configuration defined under `terraform/persistent`. There may be many 'persistent' infrastructure instances: currently `dev` and `prod` deployments have their own instances of the persistent resources. Section [Multiple Environments with Terraform Workspaces](./README.md#multiple-environments-with-terraform-workspaces) discusses this topic with more details.

## Multiple Environments with Terraform Workspace

To support infrastructure development in isolated environments, this project uses [terraform workspaces](https://developer.hashicorp.com/terraform/cli/workspaces).
The main reasons for using terraform workspaces include:
- Different workspaces allow deploying different instances of ghaf-infra. Each instance has a completely separate state data, making it possible to deploy `dev`, `prod`, or even private development instances of ghaf-infra. This makes it possible to first develop and test infrastructure changes in a private development environment, before proposing changes to shared (e.g. `dev` or `prod`) environments. The configuration codebase is the same between all the environments, with the differentiation options defined in the [`main.tf`](./main.tf#L69).
- Parts of the ghaf-infra infrastructure are persistent and shared between different environments. As an example, private `dev` environments share the binary cache storage. This arrangement makes it possible to treat, for instance, `dev` and private ghaf-infra instances dispensable: ghaf-infra instances can be temporary and short-lived as it's easy to spin-up new environments without losing any valuable data. The persistent data is configured outside the root ghaf-infra terraform deployment in the `terraform/persistent` directory. There may be many 'persistent' infrastructure instances - currently `dev` and `prod` deployments have their own instances of the persistent resources. This means that `dev` and `prod` instances of ghaf-infra do **not** share any persistent data. As an example, `dev` and `prod` deployments of ghaf-infra have a separate binary cache storage. The binding to persistent resources from ghaf-infra is done in the [`main.tf`](./main.tf#L166) based on the terraform workspace name and resource location.
- Currently, the following resources are defined 'persistent', meaning `dev` and `prod` instances do not share the following resources:
    - Binary cache storage: [`binary-cache-storage.tf`](./persistent/binary-cache-storage/binary-cache-storage.tf)
    - Binray cache signing key: [`binary-cache-sigkey.ft`](./persistent/binary-cache-sigkey/binary-cache-sigkey.tf)
    - Builder ssh key: [`builder-ssh-key.tf`](./persistent/builder-ssh-key/builder-ssh-key.tf)

To help facilitate the usage of terraform workspaces in setting-up distinct copies of ghaf-infra, one can [use terraform workspaces from the command line](https://developer.hashicorp.com/terraform/cli/workspaces#managing-cli-workspaces) or consider using the helper script provided at [`playground/terraform-playground.sh`](./playground/terraform-playground.sh). Below, for the sake of example, we use the [`playground/terraform-playground.sh`](./playground/terraform-playground.sh) to setup a private devlopment instance of ghaf-infra:

```bash
# Activate private development environment
$ ./playground/terraform-playground.sh activate
# ...
[+] Done, use terraform [validate|plan|apply] to work with your dev infra
```
Which sets-up a terraform workspace for your private development environment:
```bash
# List the current terraform worskapce
$ terraform workspace list
Terraform workspaces:
  default
  dev
* henrirosten       # <-- indicates active workspace
  prod
```

## Terraform workflow

Following describes the intended workflow, with commands executed from the nix-shell.

Once your are ready to deploy your terraform or nix configuration changes, the following sequence of commands typically take place:
```bash
# Inside the terraform directory

# Format the terraform code files:
$ terraform fmt -recursive

# Validate the terraform changes:
$ terraform validate

# Make sure you deploy to the correct ghaf-infra instance:
$ terraform workspace list
  default
  dev
* henrirosten      # <== This example deploys to private dev environment
  prod

# Show what actions terraform would take on apply:
$ terraform plan

# Apply your configuration changes:
$ terraform apply
```

Once `terraform apply` completes, the private development infrastructure is deployed.
You can now play around in your isolated copy of the infrastructure, testing and updating the changes, making sure the changes work as expected before merging the changes.

## Destroying Playground Environment
Once the configuration changes have been tested, the private development environment can be destroyed:
```bash
# Destroy the private terraform worskapce
$ ./playground/terraform-playground.sh destroy
```
The above command removes all the resources that were created for the private development environment.

## Common Terraform Errors

Below are some common Terraform errors with tips on how to resolve each.

#### Error: A resource with the ID <ID> already exists
```bash
$ terraform apply
...
azurerm_virtual_machine_extension.deploy_ubuntu_builder: Creating...
╷
│ Error: A resource with the ID "/subscriptions/<SUBID>/resourceGroups/rg-name-here/providers/Microsoft.Compute/virtualMachines/azarm/extensions/azarm-vmext" already exists - to be managed via Terraform this resource needs to be imported into the State. Please see the resource documentation for "azurerm_virtual_machine_extension" for more information.
```

Example fix:
```bash
$ terraform import azurerm_virtual_machine_extension.deploy_ubuntu_builder /subscriptions/<SUBID>/resourceGroups/rg-name-here/providers/Microsoft.Compute/virtualMachines/azarm/extensions/azarm-vmext

# Ref: https://stackoverflow.com/questions/61418168/terraform-resource-with-the-id-already-exists
```