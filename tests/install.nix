# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# In a VM with an empty virtual disk (the real host is not touched), checks that
# disko applies the disk layout of the host, the bootloader installs and the
# system reboots from disk to local-fs.target, without kexec, secrets or
# service startup. Two-disk hosts are excluded because
# disko attaches the data disk first and the test boots the first disk.
# Baseline-reset hosts need bespoke handling; aarch64 cannot run on the x86 runner.
{ self }:
self.nixosConfigurations.ghaf-lighthouse.config.system.build.installTest
