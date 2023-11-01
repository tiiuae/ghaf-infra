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

Bootstarp terraform nix-shell with the required dependencies:
```bash
$ cd terraform
$ nix-shell
```

On the first run, when starting a new configuration, you need to initialize terraform state file and plugins:
```bash
$ terraform init
```
Note: if you work with existing ghaf-infra, there should be no need to re-initialize.

## Terraform workflow
Note: working with ghaf-infra terraform configurations require access to [relevant sops secrets](./secrets.yaml). If you need access, send a PR that adds your [age public key](https://github.com/tiiuae/ghaf-infra/blob/6867a3b1e79883cb5a55108591e22fc6feb02450/docs/adapting-to-new-environments.md?plain=1#L51) to the relevant section of [.sops.yaml](https://github.com/tiiuae/ghaf-infra/blob/master/.sops.yaml) and ask review from the persons who merged the last change to that file.

Following describes the intended workflow, with commands executed from the terraform nix-shell:

- Change the terraform code by modifying the relevant files
- Format the terraform code files using command `terraform fmt`
- Test the changes using command `terraform validate`
- Once the changes are ready to be deployed, create a new PR attaching the output of `terraform plan` to the PR
- Once the PR is merged, run `terraform apply` to apply your configuration changes


## References
- Azure secrets: https://registry.terraform.io/providers/hashicorp/azuread/0.9.0/docs/guides/service_principal_client_secret
- Use Terraform to create Linux VM in azure: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/quick-create-terraform?tabs=azure-cli

