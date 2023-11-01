<!--
SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)

SPDX-License-Identifier: Apache-2.0
-->

# Ghaf-infra: Terraform

## Usage

If you still don't have nix package manager on your local host, install it following the package manager installation instructions from https://nixos.org/download.html.

Then, clone this repository:
```bash
$ git clone https://github.com/tiiuae/ghaf-infra.git
$ cd ghaf-infra
```

All the commands in this document are executed from terraform nix-shell inside the `./terraform` directory.

Bootstrap terraform nix-shell with the required dependencies:
```bash
$ cd terraform
$ nix-shell

# Authenticate with az login:
$ az login
```

## Initializing Azure Storage 
On the first run, when starting a new configuration, you need to initialize terraform state storage:
```bash
$ cd azure-storage/
$ terraform init
$ terraform apply
```
**Note**: if you work with existing ghaf-infra, there should be no need to initialize the state storage.


## Terraform workflow

Following describes the intended workflow, with commands executed from the terraform nix-shell:

- Change the terraform code by modifying the relevant files
- Format the terraform code files using command `terraform fmt`
- Test the changes using command `terraform validate`
- Once the changes are ready to be deployed, create a new PR attaching the output of `terraform plan` to the PR
- Once the PR is merged, run `terraform apply` to apply your configuration changes


## References
- Azure secrets: https://registry.terraform.io/providers/hashicorp/azuread/0.9.0/docs/guides/service_principal_client_secret
- Use Terraform to create Linux VM in azure: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/quick-create-terraform?tabs=azure-cli
