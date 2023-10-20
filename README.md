<!--
SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)

SPDX-License-Identifier: Apache-2.0
-->

# Ghaf Infra
This repository contains NixOS configurations for the Ghaf CI/CD infrastructure.

## Highlights
Flakes-based NixOS configurations for the following host profiles:
- [ghafhydra](./hosts/ghafhydra/configuration.nix):
    - [Hydra](https://nixos.wiki/wiki/Hydra) with pre-configured jobset for [ghaf](https://github.com/tiiuae/ghaf).
    - Hydra: declaratively configured with [ghaf](https://github.com/tiiuae/ghaf) flake jobset. Configured to use the host 'build01' as remote builder, as well as build on localhost.
    - Binary cache: using [nix-serve-ng](https://github.com/aristanetworks/nix-serve-ng) signing packages that can be verified with public key: `cache.ghafhydra:XQx1U4555ZzfCCQOZAjOKKPTavumCMbRNd3TJt/NzbU=`.
    - Automatic nix store garbage collection: when free disk space in `/nix/store` drops below [threshold value](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/hosts/common.nix#L46) automatically remove garbage.
    - Pre-defined users: allow ssh access for a set of users based on ssh public keys.
    - Secrets: uses [sops-nix](https://github.com/Mic92/sops-nix) to manage secrets - secrets, such as hydra admin password and binary cache signing key, are stored encrypted based on host ssh key.
    - Openssh server with pre-defined host ssh key. Server private key is stored encrypted as [sops secret](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/hosts/ghafhydra/secrets.yaml#L5) and automatically deployed on [host installation](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/tasks.py#L220).
- [build01](./hosts/build01/configuration.nix):
    - Remote builder for x86_64.
    - Openssh server with pre-defined host ssh key. Server private key is stored encrypted as [sops secret](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/hosts/build01/secrets.yaml#L1) and automatically deployed on [host installation](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/tasks.py#L220).
    - [Allows ssh access](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/hosts/build01/configuration.nix#L16) with private key '`id_buildfarm`' [stored in sops secrets](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/hosts/ghafhydra/secrets.yaml#L3) which makes it possible to use [build01](./hosts/build01/configuration.nix) as [remote builder for hydra](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/services/hydra/hydra.nix#L51).

Inspired by [nix-community infra](https://github.com/nix-community/infra), this project makes use of [pyinvoke](https://www.pyinvoke.org/) to help with common deployment [tasks](./tasks.py).

## Secrets
For deployment secrets (such as the binary cache signing key), this project uses [sops-nix](https://github.com/Mic92/sops-nix).

The general idea is: each host have `secrets.yaml` file that contains the encrypted secrets required by that host. As an example, the `secrets.yaml` file for host ghafhydra defines a secret '[`cache-sig-key`](./hosts/ghafhydra/secrets.yaml)' which is used by the host ghafhydra in [its](./hosts/ghafhydra/configuration.nix) binary cache [configuration](./modules/binarycache/binary-cache.nix) to sign the packages in the nix binary cache. All secrets in `secrets.yaml` can be decrypted with the host's ssh key - sops automatically decrypts the host secrets when the system activates (i.e. on boot or whenever nixos-rebuild switch occurs) and places the decrypted secrets in the configured file paths.

Each host's private ssh key is stored as sops secret and automatically deployed on [host installation](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/tasks.py#L220). 

The `secrets.yaml` file is created and edited with the `sops` utility. The '[`.sops.yaml`](.sops.yaml)' file tells sops what secrets get encrypted with what keys.

The secrets configuration and the usage of `sops` is adopted from [nix-community infra](https://github.com/nix-community/infra) project.

## License
This project is licensed under the Apache-2.0 license - see the [Apache-2.0.txt](LICENSES/Apache-2.0.txt) file for details.
