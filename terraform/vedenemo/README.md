<!--
SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# vedenemo

This describes a resource group holding the `az.vedenemo.dev` DNS Zone, for
which a delegation was set up, and then peeks at the Terraform states of other
environments to set up a NS delegation for `$env_shortcode.az.vedenemo.dev`,
allowing each environment to manage its DNS Records in its zones.

In the future, it might also be used to manage other resources that are not
specific to one environment.

This is using Terragrunt, like `../prod-eun`. Please refer to the `README.md`
there for more instructions.
