<!--
SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)

SPDX-License-Identifier: Apache-2.0
-->

# Ghaf Infra
This repository contains NixOS configurations for the Ghaf CI/CD infrastructure.

## Highlights
Example flakes-based NixOS configurations for host profiles '**ghafhydra**' and '**build01**':
- [ghafhydra](./hosts/ghafhydra/configuration.nix):
    - Hydra: declaratively configured using [ghaf](https://github.com/tiiuae/ghaf) jobset as an example. Hydra is configured to use host 'build01' as build machine.
    - Binary cache: with [nix-serve-ng](https://github.com/aristanetworks/nix-serve-ng) signing packages that can be verified with public key: `cache.ghafhydra:XQx1U4555ZzfCCQOZAjOKKPTavumCMbRNd3TJt/NzbU=`.
    - Automatic nix store garbage collection: when free disk space in `/nix/store` drops below [threshold value](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/hosts/common.nix#L46) automatically remove garbage.
    - Pre-defined users: allow ssh access for a set of users based on ssh public keys.
    - Secrets: uses [sops-nix](https://github.com/Mic92/sops-nix) to manage secrets - secrets, such as hydra admin password and binary cache signing key, are stored encrypted based on host ssh key
    - Openssh server with pre-defined host ssh key. Server private key is stored encrypted as [sops secret](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/hosts/ghafhydra/secrets.yaml#L5) and automatically deployed on [host installation](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/tasks.py#L220).
- [build01](./hosts/build01/configuration.nix):
    - Openssh server with pre-defined host ssh key. Server private key is stored encrypted as [sops secret](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/hosts/build01/secrets.yaml#L1) and automatically deployed on [host installation](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/tasks.py#L220).
    - [Allows ssh access](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/hosts/build01/configuration.nix#L16) with private key '`id_buildfarm`' [stored in sops secrets](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/hosts/ghafhydra/secrets.yaml#L3) which makes it possible to use [build01](./hosts/build01/configuration.nix) as [remote builder for hydra](https://github.com/tiiuae/ghaf-infra/blob/61f6765dcead5fef08ad21b793ccdec79315feae/services/hydra/hydra.nix#L51).

Inspired by [nix-community infra](https://github.com/nix-community/infra), this project also uses [pyinvoke](https://www.pyinvoke.org/) to help with common deployment [tasks](./tasks.py).

## License
This project is licensed under the Apache-2.0 license - see the [Apache-2.0.txt](LICENSES/Apache-2.0.txt) file for details.
