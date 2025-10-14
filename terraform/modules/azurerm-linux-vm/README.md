<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: Apache-2.0
-->

# azurerm-linux-vm

Terraform module spinning up a Azure VM.

This uses the `azurerm_virtual_machine` resource to spin up the VM, as it allows
data disks to be attached on boot.

This is due to
https://github.com/hashicorp/terraform-provider-azurerm/issues/6117
- with `azurerm_linux_virtual_machine` and
`azurerm_virtual_machine_data_disk_attachment` the disk only gets attached once
the VM is booted up, and the VM can't boot up if it waits for the data disk
to appear.
