<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# NetHSM

![diagram](./nethsm-setup.png)

`nethsm-gateway` runs a daemon provided by
[pkcs11-proxy](https://github.com/tiiuae/pkcs11-proxy).

This daemon is listening on tls port 2345, accessible through the nebula tunnel
from the hetzner CI. A library provided by the same project can be used as the
pkcs11 module, which will proxy the requests to the correct place (configured
through environment variables).

The requests are encrypted with a PKS key which comes from the host secrets.

Signing operations can be done from Hetzner CI, with configured pkcs11-proxy.
The keys used will be the ones stored on the NetHSM.

## SLSA Signing

Signing of blobs is done through openssl with the ED25519 keys stored in the
NetHSM.

- `GhafInfraSignBin`: Used for signing binaries
- `GhafInfraSignProv`: Used for signing provenance files

Normally signing would be done with the openssl dgst commands, but since it does
not support ED25519 keys, pkeyutl has to be used instead.

```sh
openssl pkeyutl -sign \
    -inkey "pkcs11:token=NetHSM;object=GhafInfraSignBin" \
    -in hello -rawin \
    -out hello.bin
```

Verify the signature:

```sh
openssl pkeyutl -verify \
    -inkey "pkcs11:token=NetHSM;object=GhafInfraSignBin" -pubin \
    -in hello -rawin \
    -sigfile hello.bin
```
