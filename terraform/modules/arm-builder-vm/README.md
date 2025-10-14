<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: Apache-2.0
-->

# arm-builder-vm

Terraform module spinning up a Azure aarch64 VM with ubuntu and nix.

Modified from `azurerm-linux-vm`

## Why not NixOS Image?

- `virtualisation.azure.agent` does not support anything that isn't x86, [quite explicitly](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/azure-agent.nix#L38)

- aarch64 azure vms (Standard_D2ps_v5 etc.) are all v5, and as such only support [Generation 2 hypervisor images](https://learn.microsoft.com/en-us/azure/virtual-machines/generation-2), which nix also lacks support for.
There is a [stale pull request](https://github.com/NixOS/nixpkgs/pull/236110) in nixpkgs that tries to fix this issue but it has not been active since june 2023. Part of the problem is that Gen2 images use EFI boot.

For these reasons, this arm builder is using ubuntu with nix installed on top, configured to be similar to the x86 builder's nixos configuration.
