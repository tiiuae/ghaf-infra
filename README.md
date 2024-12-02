<!--
SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Ghaf Infra

This repository contains NixOS and Terraform configuration for the [Ghaf](https://github.com/tiiuae/ghaf) CI/CD infrastructure.

## Getting Started

This document assumes you have [`nix`](https://nixos.org/download.html) package manager installed on your development host.
Experimental feature "nix-command" must be enabled.

Clone this repository:
```bash
❯ git clone https://github.com/tiiuae/ghaf-infra.git
❯ cd ghaf-infra
```

Bootstrap ghaf-infra development environment, loading the required development dependencies:
```bash
# Start a nix-shell with required dependencies:
❯ nix-shell
```

All commands referenced in the documentation are executed inside the nix-shell.

## Directory Structure
```bash
ghaf-infra
├── hosts # NixOS host configurations
│   ├── azure  # Azure ghaf-infra nix host configurations
│   │   ├── binary-cache
│   │   ├── builder
│   │   └── jenkins-controller
│   ├── builders # Stand-alone builder configurations
│   │   ├── build3
│   │   ├── build4
│   │   ├── hetzarm
│   │   └── developers.nix # Users with access to build3 and hetzarm
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
├── terraform  # Azure ghaf-infra terraform configuration
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
- `terraform/` directory contains the terraform configuration describing the image-based CI setup in Azure infra. An example instance is the 'prod' instance, which provides the Jenkins interface at: https://ghaf-jenkins-controller-prod.northeurope.cloudapp.azure.com/ as well as the Ghaf nix binary cache at: https://prod-cache.vedenemo.dev. The host configuration files in `hosts/azure` describe the NixOS configuration for the `binary-cache`, `builder`, and `jenkins-controller` hosts as outlined in [README-azure.md](https://github.com/tiiuae/ghaf-infra/blob/main/terraform/README-azure.md#image-based-builds).
- In addition to the terraform Azure infra, this repository contains NixOS configurations for various other stand-alone hosts in Ghaf CI/CD infra.
  Following are examples of some of the stand-alone configurations and their current usage in the CI/CD infrastructure:
  - `hosts/builders/hetzarm` defines the configuration for shared aarch64 builder, which currently runs in Hetzner cloud (hetzarm.vedenemo.dev). Developers can use `hetzarm.vedenemo.dev` as a remote builder for Ghaf aarch builds. Additionally, `hetzarm` is used both from Ghaf github actions and non-release Jenkins builds as a remote builder.
  - `hosts/builders/build3` defines the configuration for shared x86_64 builder, which currently runs in Ficolo cloud (builder.vedenemo.dev). Developers can use the `builder.vedenemo.dev` as a remote builder for Ghaf x86 builds.
  - `hosts/builders/build4` defines the configuration for an x86_64 builder, which currently runs in Ficolo cloud (build4.vedenemo.dev). Build4 is currently used as a remote builder both from Ghaf github actions and non-release Jenkins builds.
  - `hosts/builders/testagents/*` define the configuration for testagents used from Azure ghaf-infra.

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

### Deploy using deploy-rs
Follow the instructions at https://github.com/tiiuae/ghaf-infra/blob/main/docs/deploy-rs.md

### Deploy using tasks.py
Follow the instructions at https://github.com/tiiuae/ghaf-infra/blob/main/docs/tasks.md

### Git commit hook
This project uses git hooks to ensure the git commit message aligns with [Ghaf commit message guidelines](https://github.com/tiiuae/ghaf/blob/main/CONTRIBUTING.md#commit-message-guidelines)

To install the commit hook, run `./githooks/install-git-hooks.sh`. Commit message check [script](./githooks/check-commit.sh) will then run for all ghaf-infra git commits.
To remove the hook, run ``rm -f .git/hooks/commit-msg`` in the repository main directory.

## License
This repository uses the following licenses:

| License Full Name | SPDX Short Identifier | Description
| --- | --- | ---
| Apache License 2.0 | [Apache-2.0](https://spdx.org/licenses/Apache-2.0.html) | Source code
| Creative Commons Attribution Share Alike 4.0 International | [CC-BY-SA-4.0](https://spdx.org/licenses/CC-BY-SA-4.0.html) | Documentation
| MIT License | [MIT](https://spdx.org/licenses/MIT.html) | Source code copied from nix community projects

See `./LICENSES/` for the full license text.
