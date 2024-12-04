<!--
SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# prod-eun

This directory is an experiment, using Terragrunt for DRY.

It allows describing some redundant config only once (like provider config and
remote state).

It allows describing dependencies between different Terraform states, as well as
passing along values.

It should also make it much easier to do a granular destruction of a "leaf"
state.

It does not use Terraform Workspaces, individual instantiations have their own
files in this repository, making it possible to deviate or roll out changes in a
controlled matter.

In case the experiment proves successful, the goal is to slowly migrate
everything from the `prod-eun` environment (and other environments) to this
approach, creating sibling directories.

## Getting Started
Use `terragrunt plan` / `terragrunt apply` in each Terraform state, which are
the subdirectories in here containing a `terragrunt.hcl` file.

Terragrunt knows about inputs coming from other Terraform state outputs, so will
fetch these automatically if needed.

Use `terragrunt run-all apply` in this directory to apply changes in all
Terraform states in subdirectories (and other dependencies), accepting
dependency ordering.

Keep in mind this does not show individual plans and asks for confirmation
afterwards - use the more granular `terragrunt plan` / `terragrunt apply` on
individual states for this.
