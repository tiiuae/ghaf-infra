<!--
SPDX-FileCopyrightText: 2024 Technology Innovation Institute (TII)

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Terraform Playground

This project uses terraform to automate the creation of infrastructure resources.
To support infrastructure development in isolated development environments, we use [terraform workspaces](https://developer.hashicorp.com/terraform/cli/workspaces).

The tooling under this `playground` directory is provided to facilitate the usage of terraform workspaces in setting-up a distinct copy of the target infrastructure to test a set of changes before modifying shared (dev/prod) infrastructure.

This page documents the usage of `terraform-playground.sh` to help facilitate the usage of private development environments for testing infra changes.

**Note**: the environments created with `terraform-playground.sh` are supposed to be temporary and short-lived. Each active (non-destroyed) playground instance will cost some real money, so be sure to destroy the playground instances as soon as they are no longer needed. It's easy to spin-up a new playground environment using `terraform-playground.sh`, so there's no need to keep them alive '*just in case*'.

## Usage

If you still don't have nix package manager on your local host, install it following the package manager installation instructions from https://nixos.org/download.html.

Then, clone this repository:
```bash
$ git clone https://github.com/tiiuae/ghaf-infra.git
$ cd ghaf-infra/
```

All commands in this document are executed from nix-shell inside the `terraform/jenkins` directory.

Bootstrap nix-shell with the required dependencies:
```bash
# Start a nix-shell with required dependencies:
$ nix-shell

# Authenticate with az login:
$ az login

# We use the configuration under terraform/jenkins as an example:
$ cd terraform/jenkins
```

## Activating Playground Environment
```bash
# Activate private development environment
$ ../playground/terraform-playground.sh activate
# ...
[+] Done, use terraform [validate|plan|apply] to work with your dev infra
```
The `activate` command sets-up a terraform workspace for your private development environment:
```bash
# List the current terraform worskapce
$ ../playground/terraform-playground.sh list
Terraform workspaces:
  default
* henrirosten       # <-- indicates active workspace
```

## Testing Infrastructure Changes
With the private development workspace now setup, we can test infrastructure changes in a private development environment:
```bash
# In directory terraform/jenkins
$ pwd
[..]/ghaf-infra/terraform/jenkins

# Check terraform configuration files format:
$ terraform fmt -recursive

# Check the the terraform configuration is valid:
$ terraform validate

# Show configuration changes:
$ terraform plan

# Deploy the infrastructure:
$ terraform apply -auto-approve
```

Once `terraform apply` completes, the private development infrastructure is deployed.
You can now play around in your isolated copy of the infrastructure, testing and updating the changes, making sure the changes work as expected before proposing the changes to a shared (prod/dev) environment.

## Destroying Playground Environment
Once the configuration changes have been tested, the private development environment can be destroyed:
```bash
# Destroy the private terraform worskapce
$ ../playground/terraform-playground.sh destroy
```
The above command removes all the resources that were created for the private development environment.


## References
- Terraform workspaces: https://developer.hashicorp.com/terraform/cli/workspaces
- How to manage multiple environments with Terraform using workspaces: https://blog.gruntwork.io/how-to-manage-multiple-environments-with-terraform-using-workspaces-98680d89a03e

