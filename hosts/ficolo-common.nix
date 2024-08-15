# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  # Use ci-server as primary DNS and pfsense as secondary
  networking.nameservers = [
    "172.18.20.100"
    "172.18.20.1"
  ];
}
