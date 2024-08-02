# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{pkgs, ...}:
pkgs.rclone.overrideAttrs (oldAttrs: {
  patches =
    (oldAttrs.patches or [])
    ++ [
      # https://github.com/rclone/rclone/pull/7801
      ./http-socket-activation.patch

      # https://github.com/rclone/rclone/pull/7865
      ./webdav-introduce-unix_socket_path.patch
    ];
})
