<!--
SPDX-FileCopyrightText: 2024 Technology Innovation Institute (TII)

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Terraform Playground

This project uses terraform to automate the creation of infrastructure resources.
To support infrastructure development in isolated development environments, this project uses [terraform workspaces](https://developer.hashicorp.com/terraform/cli/workspaces).

The tooling under the `playground` directory is provided to facilitate the usage of terraform workspaces in setting-up a distinct copy of the target infrastructure to test a set of changes before modifying shared (dev/prod) infrastructure.

This page documents the usage of `terraform-playground.sh` to help facilitate the usage of private development environments for testing infra changes.

**Note**: the environments created with `terraform-playground.sh` are supposed to be temporary and short-lived. Each active (non-destroyed) playground instance will cost some real money, so be sure to destroy the playground instances as soon as they are no longer needed. It's easy to spin-up a new playground environment using `terraform-playground.sh`, so there's no need to keep them alive '*just in case*'.

## Usage

All commands in this document are executed from nix-shell inside the `terraform/` directory.

Bootstrap nix-shell with the required dependencies:
```bash
# Start a nix-shell with required dependencies:
$ nix-shell

# Authenticate with az login:
$ az login

# We use the infrastructure configuration under terraform/playground as an example:
$ cd terraform/playground
```

## Activating Playground Environment
```bash
# Activate private development environment
$ ./terraform-playground.sh activate
# ...
[+] Done, use terraform [validate|plan|apply] to work with your dev infra
```
The `activate` command sets-up a terraform workspace for your private development environment:
```bash
# List the current terraform worskapce
$ ./terraform-playground.sh list
Terraform workspaces:
  default
* henrirosten       # <-- indicates active workspace
```

## Testing Infrastructure Changes
With the private development workspace now setup, we can test infrastructure changes in a private development environment:
```bash
# In directory terraform/playground

# Check terraform configuration files format:
$ terraform fmt -recursive

# Check the the terraform configuration is valid:
$ terraform validate

# Show configuration changes:
$ terraform plan

# Deploy the infrastructure:
$ terraform apply
```

Once `terraform apply` completes, the private development infrastructure is deployed.
You can now play around in your isolated copy of the infrastructure, testing and updating the changes, making sure the changes work as expected before merging the changes.

## Destroying Playground Environment
Once the configuration changes have been tested, the private development environment can be destroyed:
```bash
# Destroy the private terraform worskapce
$ ./terraform-playground.sh destroy
```
The above command removes all the resources that were created for the private development environment.


## References
- Terraform workspaces: https://developer.hashicorp.com/terraform/cli/workspaces
- How to manage multiple environments with Terraform using workspaces: https://blog.gruntwork.io/how-to-manage-multiple-environments-with-terraform-using-workspaces-98680d89a03e
