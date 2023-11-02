# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

data "sops_file" "ghaf-infra" {
  source_file = "secrets.yaml"
}
