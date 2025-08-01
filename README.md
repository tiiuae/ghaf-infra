<!--
SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Ghaf Infra

This repository contains NixOS and Terraform configuration for the [Ghaf](https://github.com/tiiuae/ghaf) CI/CD infrastructure.

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
│   ├── azure  # Azure ghaf-infra nix host configurations (to be replaced with: hosts/hetzci/)
│   │   ├── binary-cache
│   │   ├── builder
│   │   └── jenkins-controller
│   ├── builders # Stand-alone builder configurations
│   │   ├── build1
│   │   ├── build2
│   │   ├── build3
│   │   ├── build4
│   │   ├── hetz86-1
│   │   ├── hetz86-builder
│   │   ├── hetzarm
│   │   └── developers.nix # Users with access to builder.vedenemo.dev and hetzarm.vedenemo.dev
│   ├── hetzci # Ghaf CI in hetzner (to replace azure ghaf-infra at hosts/azure)
│   ├── ...
│   └── testagent # Stand-alone testagent configurations
│       ├── dev
│       ├── prod
│       └── release
├── nix # Nix devshell, checks, deployments, etc.
├── pkgs # Patched/modified packages
├── scripts # Misc helper scripts
├── services # NixOS service modules
├── slsa # SLSA provenance buildtype document
├── terraform  # Azure ghaf-infra terraform configuration (to be replaced with: hosts/hetzci/)
│   ├── ...
│   ├── main.tf
│   ├── README-azure.md
│   └── README.md
├── users # Ghaf-infra users
...
├── README.md
├── ssh-keys.yaml # Azure ghaf-infra user ssh keys
└── tasks.py # Entrypoint for pyinvoke deployment tasks
```

Ghaf-infra repository includes configuration files for Ghaf CI/CD infrastructure.
The configuration in this repository is split in two parts:

- `terraform/` directory contains the terraform configuration describing the image-based CI setup in Azure infra. The host configuration files in `hosts/azure` describe the NixOS configuration for the `binary-cache`, `builder`, and `jenkins-controller` hosts as outlined in [README-azure.md](https://github.com/tiiuae/ghaf-infra/blob/main/terraform/README-azure.md#image-based-builds). The `terraform/` configuration will soon be retired and replaced with the configuraiton under `hosts/hetzci/`.
- In addition to the terraform Azure infra, this repository contains NixOS configurations for various other stand-alone hosts in Ghaf CI/CD infra.
  Following are examples of some of the stand-alone configurations and their current usage in the CI/CD infrastructure:
  - `hosts/builders/build1` x86_64 remote builder in Ficolo cloud (build1.vedenemo.dev). Currently, `build1` is used as a remote builder for Ghaf github actions (to be retired).
  - `hosts/builders/build2` x86_64 remote builder in Ficolo cloud (build2.vedenemo.dev). Currently, `build2` is not assigned to any specific task (to be retired).
  - `hosts/builders/build3` x86_64 remote builder in Ficolo cloud. Currently, `build3` is not assigned to any specific task (to be retired).
  - `hosts/builders/build4` x86_64 remote builder in Ficolo cloud (build4.vedenemo.dev). Currently, `build4` is not assigned to any specific task (to be retired).
  - `hosts/builders/hetz86-1` x86_64 remote builder in Hetzner cloud (hetz86-1.vedenemo.dev). Currently, `hetz86-1` is used as a remote builder for non-release Jenkins builds (both hetzci and azure).
  - `hosts/builders/hetz86-builder` x86_64 remote builder in Hetzner cloud (builder.vedenemo.dev). Developers can use the builder.vedenemo.dev as a remote builder for Ghaf x86 builds.
  - `hosts/builders/hetzarm` aarch64 remote builder in Hetzner cloud (hetzarm.vedenemo.dev). Developers can use `hetzarm.vedenemo.dev` as a remote builder for Ghaf aarch builds. Additionally, `hetzarm` is used both from Ghaf github actions and non-release Jenkins builds as a remote builder.
  - `hosts/builders/hetzci` See: https://github.com/tiiuae/ghaf-infra/blob/main/hosts/hetzci/README.md.
  - `hosts/builders/testagents/*` define the configuration for testagents used from ghaf-infra Jenkins instances.

Usage and deployment of the Azure infra is described in [`terraform/README.md`](https://github.com/tiiuae/ghaf-infra/blob/main/terraform/README.md).
Following sections describe the intended usage and deployment of the stand-alone NixOS configurations.

## Usage

**Important**:
The configuration files in this repository declaratively define the system configuration for all hosts in the Ghaf CI/CD infrastructure. That is, all system configurations - including the secrets - are stored and version controlled in this repository. Indeed, all the hosts in the infrastructure might be reinstalled without further notice, so do not assume that anything outside the configurations defined in this repository would be available in the hosts. This includes the administrator's home directories: do not keep any important data in your home, since the contents of `/home` might be deleted without further notice.

### Secrets

For deployment secrets (such as the binary cache signing key), this project uses [sops-nix](https://github.com/Mic92/sops-nix).

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
- [Deploy](./docs/deploy-rs.md) the new configuration to changed hosts (build3, hetzarm).

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
