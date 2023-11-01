<!--
SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)

SPDX-License-Identifier: Apache-2.0
-->

# Ghaf-infra: Terraform Configuration

## Usage

Assuming you have nix package manager installed locally:

First, clone this repository:
```bash
$ git clone https://github.com/tiiuae/ghaf-infra.git
$ cd ghaf-infra
```

All example commands in this document are executed from terraform nix-shell inside the [`terraform`](../terraform/) directory.
Start a terraform nix-shell:
```bash
$ cd terraform
$ nix-shell
```

Then, initialize terraform state file and plugins:
```bash
$ terraform init
```

## Terraform workflow
Following describes the intended workflow:
- Change the terraform configurations by modifying the files at [`terraform`](../terraform/)
- Format the terraform configuration files using command `terraform fmt`
- Test the changes using command `terraform validate`
- Once the changes are ready to be deployed, create a new PR attaching the output of `terraform plan` to the PR.
- Once the PR is merged, run `terraform apply` to apply the changes. Notice: this last step requires admin access to [terraform sops secrets](https://github.com/tiiuae/ghaf-infra/blob/489b1947d443907bbbd3676f6126fc28d6ebee8d/.sops.yaml#L12)


## References
- Azure secrets: https://registry.terraform.io/providers/hashicorp/azuread/0.9.0/docs/guides/service_principal_client_secret
- Use Terraform to create Linux VM in azure: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/quick-create-terraform?tabs=azure-cli

