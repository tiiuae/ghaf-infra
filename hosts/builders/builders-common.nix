# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # Specifies the maximum number of concurrent unauthenticated connections to the SSH daemon.
  # The default of 10 is not enough when multiple clients are building
  # at the same time and can result in dropped connections
  services.openssh.settings = {
    MaxStartups = 100;
  };
  # Increase the maximum number of open files user limit, see ulimit
  security.pam.loginLimits = [
    {
      domain = "*";
      item = "nofile";
      type = "-";
      value = "8192";
    }
  ];
}
