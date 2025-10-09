<!--
SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Nethsm Gateway

## Softhsm usage

Manual steps of how the softhsm is used. This can be automated with scripts in
the future.

### Creating softhsm signing keys

> Prerequisite of key creation is that you are in the `softhsm` group.

First define the pins as variables:

```sh
export PIN=1234
export SO_PIN=123456
export TOKEN=testkey
```

Init new softhsm token slot:

```sh
softhsm2-util --init-token --free --label $TOKEN --so-pin $SO_PIN --pin $PIN

# or populate the SLOT automatically
export SLOT=$(
    softhsm2-util --init-token --free --label $TOKEN \
    --so-pin $SO_PIN --pin $PIN | grep "to slot " | awk '{print $NF}'
) && echo $SLOT
```

It will print the slot number to use in following commands. Save this to a
variable as well:

```sh
export SLOT=391264627 # replace with the randomly assigned slot you got back
```

```sh
pkcs11-tool --module $SOFTHSM2_MODULE -p $PIN --slot $SLOT \
            --keypairgen --key-type rsa:4096 --label "PK-key" --id 01

pkcs11-tool --module $SOFTHSM2_MODULE -p $PIN --slot $SLOT \
            --keypairgen --key-type rsa:4096 --label "KEK-key" --id 02

pkcs11-tool --module $SOFTHSM2_MODULE -p $PIN --slot $SLOT \
            --keypairgen --key-type rsa:4096 --label "DB-key" --id 03
```

Verify keys are there. You should see 3 public keys and 3 private keys.

```sh
pkcs11-tool --module $SOFTHSM2_MODULE -p $PIN --slot $SLOT --list-objects
```

### Creating certificates

> `$KEYDIR` is defined in the system configuration.

Now you can use the created private keys to generate x509 certificates:

```sh
# PK
openssl req -new -x509 -sha256 -days 365 \
        -key "pkcs11:token=$TOKEN;object=PK-key;type=private;pin-value=$PIN" \
        -config $OPENSSL_EXTRA_CONF/create_PK_cert.ini \
        -out $KEYDIR/pk.crt
# KEK
openssl req -new -x509 -sha256 -days 365 \
        -key "pkcs11:token=$TOKEN;object=KEK-key;type=private;pin-value=$PIN" \
        -config $OPENSSL_EXTRA_CONF/create_KEK_cert.ini \
        -out $KEYDIR/kek.crt
# DB
openssl req -new -x509 -sha256 -days 365 \
        -key "pkcs11:token=$TOKEN;object=DB-key;type=private;pin-value=$PIN" \
        -config $OPENSSL_EXTRA_CONF/create_DB_cert.ini \
        -out $KEYDIR/db.crt
```

You can import these certificates into the softhsm:

```sh
pkcs11-tool --module $SOFTHSM2_MODULE -p 1234 --slot $SLOT \
            --write-object $KEYDIR/pk.crt --type cert --label PK-cert

pkcs11-tool --module $SOFTHSM2_MODULE -p 1234 --slot $SLOT \
            --write-object $KEYDIR/kek.crt --type cert --label KEK-cert

pkcs11-tool --module $SOFTHSM2_MODULE -p 1234 --slot $SLOT \
            --write-object $KEYDIR/db.crt --type cert --label DB-cert
```

### Exporting public keys

The public keys can be exported for enrollment to UEFI if needed.

```sh
pkcs11-tool --module $SOFTHSM2_MODULE -p $PIN --slot $SLOT \
            --read-object --type pubkey --label PK-key -o $KEYDIR/pk.der
pkcs11-tool --module $SOFTHSM2_MODULE -p $PIN --slot $SLOT \
            --read-object --type pubkey --label KEK-key -o $KEYDIR/kek.der
pkcs11-tool --module $SOFTHSM2_MODULE -p $PIN --slot $SLOT \
            --read-object --type pubkey --label DB-key -o $KEYDIR/db.der
```

## Signing EFI file using sbsign

> Locally on the nethsm-gateway

Sign your EFI bootloader using private key and certificate stored on the
softhsm. `systemd-sbsign` can use the openssl pkcs11 provider to pull those
objects.

```sh
systemd-sbsign sign \
    --private-key-source provider:pkcs11 \
    --private-key "pkcs11:token=$TOKEN;object=DB-key;type=private;pin-value=$PIN" \
    --certificate-source provider:pkcs11 \
    --certificate "pkcs11:token=$TOKEN;object=DB-cert;type=cert;pin-value=$PIN" \
    --output SIGNED_BOOT.EFI \
    YOUR_BOOT.EFI
```

## PKCS11 proxy

`nethsm-gateway` runs a daemon provided by
[pkcs11-proxy](https://github.com/scobiej/pkcs11-proxy/tree/osx-openssl1-1).

This daemon is listening on tls port 2345, accessible through the nebula tunnel
from our hetzner CI. A library provided by the same project should be used as
the pkcs11 module, and requests encrypted with a tls identity.

### Signing and verifying using cosign

> This happens on hetzner through pkcs11-proxy.

Given an arbitrary file `hello`, and signing key `SLSA-key` with both private
and public keys on the HSM (creation left as exercise for the reader):

```sh
cosign sign-blob --yes \
    --key "pkcs11:token=$TOKEN;slot-id=$SLOT;object=SLSA-key?module-path=$PKCS11_PROXY_MODULE&pin-value=$PIN" \
    --output-file hello.sig \
    hello
```

Now you have hello and hello.sig files. Verify the signature like so:

```sh
cosign verify-blob \
    --key "pkcs11:token=$TOKEN;slot-id=$SLOT;object=SLSA-key;type=pubkey?module-path=$PKCS11_PROXY_MODULE&pin-value=$PIN" \
    --signature hello.sig \
    hello
```

### UEFI Signing through proxy

TODO
