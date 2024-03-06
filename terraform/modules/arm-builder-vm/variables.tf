# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "virtual_machine_name" {
  type = string
}

variable "virtual_machine_size" {
  type = string
}

variable "virtual_machine_osdisk_size" {
  type = string
}

variable "virtual_machine_custom_data" {
  type    = string
  default = ""
}

variable "allocate_public_ip" {
  type    = bool
  default = false
}

variable "subnet_id" {
  type        = string
  description = "The subnet ID to attach to the VM and allocate an IP from"
}

variable "data_disks" {
  description = "List of dict containing keys of the storage_data_disk block"
  default     = []
}
