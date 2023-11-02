<!--
SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)

SPDX-License-Identifier: Apache-2.0
-->

# Ghaf-infra: Terraform

This project uses terraform to automate the creation of infrastructure resources. The inteded usage together with NixOS configurations in the main [flake.nix](../flake.nix) is as follows:
- We use the terraform configuration in this directory for the inital setup of the infrastructure resources (VMs, networks, etc.)
- We use the NixOS configurations in [flake.nix](../flake.nix) to [install](../README.md#install) NixOS on the VMs
- We maintain the infrastructure by [deploying](../README.md#deploy) changes to the NixOS configurations via [flake.nix](../flake.nix)

Notice: the typical ghaf-infra maintenance only requires deploying changes to the existing infra. Indeed, the infrastructure setup with terraform and installation of NixOS are tasks only required when moving to a new infrastructure or introducing new resources to the existing infra.

## Usage

If you still don't have nix package manager on your local host, install it following the package manager installation instructions from https://nixos.org/download.html.

Then, clone this repository:
```bash
$ git clone https://github.com/tiiuae/ghaf-infra.git
$ cd ghaf-infra
```

All commands in this document are executed from terraform nix-shell inside the `terraform` directory.

Bootstrap terraform nix-shell with the required dependencies:
```bash
$ cd terraform
$ nix-shell

# Authenticate with az login:
$ az login
```

## Initializing Azure Storage 
This project stores the terraform state in a remote storage in an azure storage blob as configured in [tfstate-storage.tf](./azure-storage/tfstate-storage.tf). The benefits of using such remote storage setup are well outlined in [storing state in azure storage](https://learn.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage) and [terraform backend configuration](https://developer.hashicorp.com/terraform/language/settings/backends/configuration).

**Note**: if you work with existing infrastructure, there should be no need to initialize the state storage. Initializing state storage is only needed when you start-off or move to a new infrastructure.

When starting a new infrastructure you need to initialize the terraform state storage:
```bash
$ cd azure-storage/
$ terraform init
$ terraform apply
```

## Terraform workflow

Following describes the intended workflow, with commands executed from the terraform nix-shell.

First, change the terraform code by modifying the relevant files in this directory. Then:

```bash
# Format the terraform code files:
$ terraform fmt

# Test the changes:
$ terraform validate

# Once the changes are ready to be deployed, create a new PR
# attaching the output of `terraform plan` to the PR:
$ terraform plan

# Once the PR is merged, apply your configuration changes:
$ terraform apply
```

## References
- Azure secrets: https://registry.terraform.io/providers/hashicorp/azuread/0.9.0/docs/guides/service_principal_client_secret
- Use Terraform to create Linux VM in azure: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/quick-create-terraform?tabs=azure-cli
