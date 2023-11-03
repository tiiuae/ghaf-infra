# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

variable "resource_group_location" {
  type        = string
  default     = "swedencentral"
  description = "Location of the resource group."
}


variable "resourcegroup" {
  description = "The Azure Resource Group Name within your Subscription in which this resource will be created."
  default     = "ghaf-infra-swe"
}

variable "resource_group_name_prefix" {
  type        = string
  default     = "rg"
  description = "Prefix of the resource group name that's combined with a random ID so name is unique in your Azure subscription."
}

variable "location" {
  description = "Location for resources"
  default     = "eastus"
}

variable "subnet_address_prefix" {
  description = "Address prefix for subnet"
  default     = "10.0.1.0/24"
}