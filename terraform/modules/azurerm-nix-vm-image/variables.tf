# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

variable "nix_attrpath" {
  type        = string
  description = "Nix attribute path building a directory containing a disk.vhd file"
}

variable "nix_entrypoint" {
  type        = string
  description = "Path to the .nix file exposing the attribute path"
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "storage_account_name" {
  type = string
}

variable "storage_container_name" {
  type = string
}

variable "name" {
  type        = string
  description = "Name of the VM image."
}

