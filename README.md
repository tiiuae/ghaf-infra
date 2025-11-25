<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Ghaf Infra

This repository contains NixOS configuration for the [Ghaf](https://github.com/tiiuae/ghaf) CI/CD infrastructure.

## Getting Started

This document assumes you have [`nix`](https://nixos.org/download.html) with flakes support.

Clone this repository:

```bash
❯ git clone https://github.com/tiiuae/ghaf-infra.git
❯ cd ghaf-infra
```

Bootstrap nix shell with the required dependencies:

```bash
❯ nix develop
```

All commands referenced in the documentation are executed inside the nix-shell.

## Directory Structure

```bash
ghaf-infra
├── hosts # NixOS host configurations
│   ├── builders # Builder configurations
│   │   ├── hetz86-1 # x86_64 remote builder for non-release CI builds
│   │   ├── hetz86-builder # x86_64 remote builder (builder.vedenemo.dev) for developers
│   │   ├── hetz86-rel-1 # x86_64 remote builder for release CI builds
│   │   ├── hetzarm # aarch64 remote builder (hetzarm.vedenemo.dev) for both non-release CI and developer builds
│   │   ├── hetzarm-rel-1 # aarch64 remote builder for release CI builds
│   │   └── ...
│   ├── hetzci # Ghaf CI in hetzner: see hetzci/README.md
│   ├── ghaf-auth # See: docs/jenkins-authentication.md
│   ├── ghaf-fleetdm
│   ├── ghaf-lighthouse # See: docs/nebula.md
│   ├── ghaf-log # See: https://ghaflogs.vedenemo.dev
│   ├── ghaf-monitoring # See: https://monitoring.vedenemo.dev
│   ├── ghaf-proxy # Proxy host: ghaf-proxy.vedenemo.dev
│   ├── ghaf-webserver
│   └── testagent # See: docs/jenkins-testagents.md
│       ├── dev
│       ├── prod
│       ├── release
│       └── ...
├── nix # Nix devshell, checks, deployments, etc.
├── pkgs # Patched/modified packages
├── scripts # Misc helper scripts
├── services # NixOS service modules
├── slsa # SLSA provenance buildtype document
├── users # Ghaf-infra users
...
├── README.md
└── tasks.py # See: docs/tasks.md
```

## Usage

**Important**:
The configuration files in this repository declaratively define the system configuration for all hosts in the Ghaf CI/CD infrastructure. That is, all system configurations - including the secrets - are stored and version controlled in this repository. Indeed, all the hosts in the infrastructure might be reinstalled without further notice, so do not assume that anything outside the configurations defined in this repository would be available in the hosts. This includes the administrator's home directories: do not keep any important data in your home, since the contents of `/home` might be deleted without further notice.

### Secrets

For deployment secrets (such as the ssh host key), this project uses [sops-nix](https://github.com/Mic92/sops-nix).

The general idea is: each host have `secrets.yaml` file that contains the encrypted secrets required by that host. As an example, the `secrets.yaml` file for the host ghaf-proxy defines a secret [`loki_password`](https://github.com/tiiuae/ghaf-infra/blob/6be2cb637af86ddb1abd8bfb60160f81ce6581ca/hosts/ghaf-proxy/secrets.yaml#L2) which is used by the host ghaf-proxy in [its](https://github.com/tiiuae/ghaf-infra/blob/6be2cb637af86ddb1abd8bfb60160f81ce6581ca/hosts/ghaf-proxy/configuration.nix#L51) monitoring service configuration to push logs to Grafana Loki. All secrets in `secrets.yaml` can be decrypted with each host's ssh key - sops automatically decrypts the host secrets when the system activates (i.e. on boot or whenever nixos-rebuild switch occurs) and places the decrypted secrets in the configured file paths. An [admin user](https://github.com/tiiuae/ghaf-infra/blob/6be2cb637af86ddb1abd8bfb60160f81ce6581ca/.sops.yaml#L6-L12) manages the secrets by using the `sops` command line tool.

Each host's private ssh key is stored as sops secret and automatically deployed on [host installation](https://github.com/tiiuae/ghaf-infra/blob/6be2cb637af86ddb1abd8bfb60160f81ce6581ca/tasks.py#L438).

`secrets.yaml` files are created and edited with the `sops` utility. The [`.sops.yaml`](.sops.yaml) file tells sops what secrets get encrypted with what keys.

The secrets configuration and the usage of `sops` is adopted from [nix-community infra](https://github.com/nix-community/infra) project.

### Onboarding new remote builder users

Onboarding new users to remote builders require the following manual steps:

- Add their user and ssh key to [developers](./hosts/builders/developers.nix).
- [Deploy](./docs/deploy-rs.md) the new configuration to changed hosts.

### Onboarding new admins

Onboarding new admins require the following manual steps:

- Add their user and ssh key to [users](./users/) and import the user on the hosts they need access to.
- If they need to manage sops secrets, add their [age key](./docs/adapting-to-new-environments.md#add-your-admin-sops-key) to [.sops.yaml](.sops.yaml), update the `creation_rules`, and run the [`update-sops-files`](./docs/tasks.md#update-sops-files) task.
- [Deploy](./docs/deploy-rs.md) the new configuration to changed hosts.

### Hetzci development

See the README at https://github.com/tiiuae/ghaf-infra/blob/main/hosts/hetzci/README.md


### Deploy changes using deploy-rs

Follow the instructions at <https://github.com/tiiuae/ghaf-infra/blob/main/docs/deploy-rs.md>


## License

This repository uses the following licenses:

| License Full Name | SPDX Short Identifier | Description
| --- | --- | ---
| Apache License 2.0 | [Apache-2.0](https://spdx.org/licenses/Apache-2.0.html) | Source code
| Creative Commons Attribution Share Alike 4.0 International | [CC-BY-SA-4.0](https://spdx.org/licenses/CC-BY-SA-4.0.html) | Documentation
| MIT License | [MIT](https://spdx.org/licenses/MIT.html) | Source code copied from nix community projects

See `./LICENSES/` for the full license text.
