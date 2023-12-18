# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

# Create a ED25519 key, which the jenkins master will use to authenticate with
# builders.
resource "tls_private_key" "ed25519_remote_build" {
  algorithm = "ED25519"
}

# Dump the ed25519 public key to disk
resource "local_file" "ed25519_remote_build_pubkey" {
  filename        = "${path.module}/id_ed25519_remote_build.pub"
  file_permission = "0644"
  content         = tls_private_key.ed25519_remote_build.public_key_openssh
}
