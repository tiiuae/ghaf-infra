<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Ghaf Infra

This repository declaratively defines the NixOS configuration for the [Ghaf](https://github.com/tiiuae/ghaf) CI/CD infrastructure. All host configurations (including secrets) are version-controlled here.

## Overview

The infrastructure includes:
- **Jenkins CI environments** (prod, dev, release) hosted at Hetzner
- **Multi-architecture remote builders** for x86_64 and aarch64
- **On-prem test agents** with connected hardware devices
- **Supporting services**: monitoring, logging, authentication, [Nebula](./docs/nebula.md) overlay network, [NetHSM](./docs/nethsm.md) hardware signing, and an OCI container registry
- **Secrets management** via [sops-nix](https://github.com/Mic92/sops-nix) (see [architecture overview](./docs/architecture.md#secrets-management))

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

```
ghaf-infra
├── docs/               # Documentation (see Documentation section below)
├── hosts/              # NixOS host configurations
│   ├── builders/       # Remote builder machines
│   ├── hetzci/         # Jenkins CI environments (see hetzci/README.md)
│   ├── testagent/      # On-prem test agents
│   ├── ghaf-*/         # Supporting services (monitoring, auth, registry, etc.)
│   └── machines.nix    # Host inventory (IPs, keys, Nebula addresses)
├── nix/                # Flake plumbing (deployments, apps, git-hooks)
├── scripts/            # Operational scripts
├── services/           # Shared NixOS service modules
├── users/              # Admin user configurations
└── tasks.py            # Invoke tasks (see docs/tasks.md)
```

## Documentation

- [Architecture overview](./docs/architecture.md) — how all the pieces fit together
- [Adding a new host](./docs/adding-a-host.md) — step-by-step runbook for onboarding a host
- [Deployment tasks](./docs/tasks.md) — install, reboot, and other operational tasks
- [Deploying with deploy-rs](./docs/deploy-rs.md) — how to deploy configuration changes
- [Monitoring](./docs/monitoring.md) — Grafana and Prometheus setup
- [Nebula overlay network](./docs/nebula.md) — network connectivity between hosts
- [NetHSM hardware signing](./docs/nethsm.md) — hardware-backed signing
- [Jenkins authentication](./docs/jenkins-authentication.md) — Jenkins auth setup
- [Jenkins test agents](./docs/jenkins-testagents.md) — on-prem test agents
- [Jenkins CI development](./hosts/hetzci/README.md) — developing the CI environment

## Common Tasks

- **Deploy configuration changes** — [deploy-rs](./docs/deploy-rs.md)
- **Add a new host** — [adding a host](./docs/adding-a-host.md)
- **Add a remote builder user** — add their SSH key to
  [developers.nix](./hosts/builders/developers.nix), then deploy
- **Onboard a new admin** — add their user to [users/](./users/),
  optionally add their age key to [.sops.yaml](.sops.yaml) and run
  [`inv update-sops-files`](./docs/tasks.md#update-sops-files), then deploy
- **Manage secrets** — [secrets management](./docs/architecture.md#secrets-management)
- **Install, reboot, and other operational tasks** — [tasks](./docs/tasks.md)

**Note**: Hosts may be reinstalled at any time. Do not store important
data outside the configurations in this repository — including in `/home`
directories on the hosts.

## License

This project is REUSE-compliant. See [`LICENSES/`](./LICENSES/) and the SPDX headers in each file.
