<!--
SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)

SPDX-License-Identifier: Apache-2.0
-->

# Ghaf Infra
This repository contains NixOS configurations for the [Ghaf](https://github.com/tiiuae/ghaf) CI/CD infrastructure.

## Highlights
Flakes-based NixOS configurations for the following host profiles:
- [ghafhydra](./hosts/ghafhydra/configuration.nix):
    - [Hydra](https://nixos.wiki/wiki/Hydra) with pre-configured jobset for Ghaf.
    - Hydra: declaratively configured with Ghaf flake jobset, using the host 'build01' as remote builder as well as build on localhost.
    - Binary cache: using [nix-serve-ng](https://github.com/aristanetworks/nix-serve-ng) signing packages that can be verified with public key: `cache.ghafhydra:XQx1U4555ZzfCCQOZAjOKKPTavumCMbRNd3TJt/NzbU=`.
    - Automatic nix store garbage collection: when free disk space in `/nix/store` drops below [threshold value](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/hosts/common.nix#L46) automatically remove garbage.
    - Pre-defined users: allow ssh access for a set of users based on ssh public keys.
    - Secrets: uses [sops-nix](https://github.com/Mic92/sops-nix) to manage secrets - secrets, such as hydra admin password and binary cache signing key, are stored encrypted based on host ssh key.
    - Openssh server with pre-defined host ssh key. Server private key is stored encrypted as [sops secret](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/hosts/ghafhydra/secrets.yaml#L5) and automatically deployed on [host installation](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/tasks.py#L243).
- [build01](./hosts/build01/configuration.nix):
    - Remote builder for hydra.
    - Openssh server with pre-defined host ssh key. Server private key is stored encrypted as [sops secret](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/hosts/build01/secrets.yaml#L1) and automatically deployed on [host installation](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/tasks.py#L243).
    - Extensible buildfarm setup: build01 [allows ssh access](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/hosts/build01/configuration.nix#L16) with private key `id_buildfarm` [stored in sops secrets](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/hosts/ghafhydra/secrets.yaml#L3) on the hosts that need access to the builder. This setup makes it possible to use [build01](./hosts/build01/configuration.nix) and other hosts that are accessible with `id_buildfarm` as a [remote builder for hydra](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/services/hydra/hydra.nix#L61).

Inspired by [nix-community infra](https://github.com/nix-community/infra), this project makes use of [pyinvoke](https://www.pyinvoke.org/) to help with common deployment [tasks](./tasks.py).

## Secrets
For deployment secrets (such as the binary cache signing key), this project uses [sops-nix](https://github.com/Mic92/sops-nix).

The general idea is: each host have `secrets.yaml` file that contains the encrypted secrets required by that host. As an example, the `secrets.yaml` file for the host ghafhydra defines a secret [`cache-sig-key`](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/hosts/ghafhydra/secrets.yaml#L2) which is used by the host ghafhydra in [its](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/hosts/ghafhydra/configuration.nix#L15) binary cache [configuration](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/services/binarycache/binary-cache.nix#L12) to sign packages in the nix binary cache. All secrets in `secrets.yaml` can be decrypted with each host's ssh key - sops automatically decrypts the host secrets when the system activates (i.e. on boot or whenever nixos-rebuild switch occurs) and places the decrypted secrets in the configured file paths. An [admin user](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/.sops.yaml#L6) manages the secrets by using the `sops` command line tool.

Each host's private ssh key is stored as sops secret and automatically deployed on [host installation](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/tasks.py#L243). 

The `secrets.yaml` file is created and edited with the `sops` utility. The [`.sops.yaml`](.sops.yaml) file tells sops what secrets get encrypted with what keys.

The secrets configuration and the usage of `sops` is adopted from [nix-community infra](https://github.com/nix-community/infra) project.

## License
This project is licensed under the Apache-2.0 license - see the [Apache-2.0.txt](LICENSES/Apache-2.0.txt) file for details.
