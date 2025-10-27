<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# NetHSM

## Signing

Signing of blobs is done through openssl with the ED25519 keys stored in the
NetHSM.

- `GhafInfraSignBin`: Used for signing binaries
- `GhafInfraSignProv`: Used for signing provenance files

Normally signing would be done with the openssl dgst commands, but since it does
not support ED25519 keys, pkeyutl has to be used instead.

```sh
openssl pkeyutl -sign \
    -inkey "pkcs11:object=GhafInfraSignBin" \
    -in hello -rawin \
    -out hello.bin
```

Verify the signature:

```sh
openssl pkeyutl -verify \
    -inkey "pkcs11:object=GhafInfraSignBin" -pubin \
    -in hello -rawin \
    -sigfile hello.bin
```
