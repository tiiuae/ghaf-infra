# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

variable "resource_tags" {
  description = "Tags to set for all resources based on environments"
  type        = map(string)
  default     = {
    application     = "ghaf-infra",
    environment = "dev",
    owner = "Kai",
    project = "project",
    functionalrole = "CI",
    department = "CRC",
  }
}
