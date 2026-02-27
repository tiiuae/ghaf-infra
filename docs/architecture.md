<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Architecture Overview

This document describes the high-level architecture of the
[Ghaf](https://github.com/tiiuae/ghaf) CI/CD infrastructure. For operational
procedures and per-component details, see the [cross-references](#cross-references)
at the end.

## Host Overview

The full host inventory (IPs, SSH keys, Nebula addresses) lives in
[`hosts/machines.nix`](../hosts/machines.nix). The sections below group hosts
by role and describe how they relate to one another.

### Jenkins Controllers

Four Jenkins controller instances serve different stages of the development
lifecycle. Each runs behind an OAuth2 Proxy that authenticates users via
ghaf-auth and exposes a public web UI over Caddy with ACME TLS.

| Host | URL | Purpose |
|---|---|---|
| `hetzci-prod` | ci-prod.vedenemo.dev | Production CI — runs on every push and PR to Ghaf |
| `hetzci-dev` | ci-dev.vedenemo.dev | Development CI — for CI and hardware-test development |
| `hetzci-release` | ci-release.vedenemo.dev | Release CI — ephemeral, re-installed per release cycle |
| `hetzci-dbg` | ci-dbg.vedenemo.dev | Debug CI — isolated environment for troubleshooting |

A fifth configuration, `hetzci-vm`, is not deployed — it runs locally
(`localhost:8080`) via `nix run .#run-hetzci-vm` as a QEMU VM for developing
and testing CI changes before deploying to a real environment.

GitHub webhooks deliver push and PR events to `hetzci-prod`. The release
controller has no webhooks; its pipelines are triggered manually. Each
controller dispatches Nix builds to its own set of remote builders and
connects to test agents over the Nebula overlay.

### Remote Builders

Builders are high-resource Hetzner machines that compile Nix derivations on
behalf of Jenkins controllers, GitHub Actions, and individual developers. Each
Jenkins controller has a dedicated builder set to isolate workloads.

| Host | Arch | Used by |
|---|---|---|
| `hetz86-1` | x86_64 | `hetzci-prod`, `hetzci-dev` |
| `hetz86-builder` | x86_64 | GitHub Actions, developer remote builds (builder.vedenemo.dev) |
| `hetzarm` | aarch64 | `hetzci-prod`, `hetzci-dev`, GitHub Actions, developer remote builds |
| `hetz86-rel-2` | x86_64 | `hetzci-release` |
| `hetzarm-rel-1` | aarch64 | `hetzci-release` |
| `hetz86-dbg-1` | x86_64 | `hetzci-dbg` |
| `hetzarm-dbg-1` | aarch64 | `hetzci-dbg` |

Build results are pushed to two Cachix binary caches:

- **[`ghaf-dev`](https://app.cachix.org/organization/tiiuae/cache/ghaf-dev)** — populated by prod/dev CI on every PR authored by a `tiiuae`
  organization member. This is the main cache used during day-to-day
  development.
- **[`ghaf-release`](https://app.cachix.org/organization/tiiuae/cache/ghaf-release)** — populated exclusively by the release environment. The
  ephemeral release controller and builders pull earlier build results from this
  cache so that only changed derivations need to be rebuilt.

### Test Agents

Test agents are on-prem machines in the Tampere office with physical hardware
devices (Orin AGX/NX, Lenovo X1, Dell, etc.) attached. They connect to Jenkins
controllers over the Nebula overlay and run one Jenkins agent service per
device, effectively acting as a lock for each piece of hardware.

| Host | Variant | Hardware |
|---|---|---|
| `testagent-dev` | dev | Orin AGX, Orin NX, Orin AGX-64, Lenovo X1, Dell 7330, Darter Pro |
| `testagent-prod` | prod | Lenovo X1, Dell 7330, Darter Pro |
| `testagent2-prod` | prod | (secondary prod agent) |
| `testagent-release` | release | Orin AGX, Orin NX, Lenovo X1, Darter Pro |

Each agent also runs:

- [BrainStem](https://acroname.com/software/brainstem-development-kit) — CLI
  tools and udev rules for controlling Acroname programmable USB hubs (used for
  power-cycling and USB switching of test devices)
- `policy-checker` — a Go wrapper around `verify-signature` that validates SLSA
  provenance and image signatures before flashing

Agents expose relay-board metrics (port 8000) and push logs to Loki via Alloy.
They are monitored by `ghaf-monitoring` through the Nebula overlay.

### Supporting Services

| Host | Service | Purpose |
|---|---|---|
| `ghaf-auth` | [Dex](https://dexidp.io/) OIDC provider | Central authentication backed by GitHub org membership |
| `ghaf-monitoring` | Prometheus, Grafana, Loki | **Infrastructure** metrics, dashboards, log aggregation, and alerting (monitoring.vedenemo.dev) |
| `ghaf-log` | Grafana + Loki | **Ghaf device** log analysis (ghaflogs.vedenemo.dev) |
| `ghaf-lighthouse` | Nebula lighthouse | Overlay network discovery and DNS for `sumu.vedenemo.dev` |
| `ghaf-registry` | [Zot](https://zotregistry.dev/) OCI registry | Container image registry (registry.vedenemo.dev), OIDC-authenticated via ghaf-auth |
| `ghaf-webserver` | Nginx | Static web content (vedenemo.dev) |
| `ghaf-fleetdm` | [Fleet](https://fleetdm.com/) (fleetdm.vedenemo.dev) | Device management server for Ghaf end-devices — test agents carry enrollment credentials (via sops) so that Ghaf images flashed during CI testing can register with Fleet |

### NetHSM Gateways

CI builds use hardware security modules (HSMs) for two independent signing
purposes:

- **SLSA signing** — disk images and provenance files are signed for supply
  chain integrity. This uses `openssl` with ECDSA/EDDSA keys stored on the
  NetHSM.
- **UEFI Secure Boot signing** — EFI binaries and boot images are signed so
  they pass Secure Boot verification on target hardware. This uses
  `uefisign`/`systemd-sbsign` with RSA keys stored on the HSM.

Both operations go through the same PKCS#11 proxy infrastructure, but use
different keys and tools. See [NetHSM hardware signing](./nethsm.md) for key
names, signing commands, and UEFI key enrollment.

The signing keys are stored on dedicated
[NetHSM](https://www.nitrokey.com/products/nethsm) hardware, physically
isolated from the CI network. Gateway hosts bridge this gap: each sits on an
isolated ethernet segment with the NetHSM appliance and exposes a PKCS#11
interface over the Nebula overlay so that Jenkins controllers can request
signing operations without direct access to the HSM.

| Host | Location | NetHSM address |
|---|---|---|
| `nethsm-gateway` | Tampere office | 192.168.70.10 (isolated ethernet) |
| `uae-nethsm-gateway` | UAE site | local network |

Each gateway runs a `pkcs11-proxy` daemon on a TLS port reachable from the
Nebula network. Requests are encrypted with a host-specific key from sops
secrets.

### UAE Site

A parallel set of infrastructure in the UAE mirrors parts of the Hetzner setup
and connects back via the Nebula overlay.

| Host | Purpose |
|---|---|
| `uae-azureci-prod` | Azure-hosted Jenkins controller (ci-prod.uaenorth.cloudapp.azure.com) |
| `uae-azureci-az86-1` | x86_64 builder in Azure for uae-azureci-prod |
| `uae-testagent-prod` | On-prem test agent with hardware devices |
| `uae-lab-node1` | Lab node with Kubernetes tooling |
| `uae-nethsm-gateway` | NetHSM signing gateway (see above) |

## CI/CD Pipeline Flow

Changes to the Ghaf repository trigger two parallel build paths:

### Jenkins Pipeline

1. **Trigger** — a push or PR to the [Ghaf](https://github.com/tiiuae/ghaf)
   repo sends a GitHub webhook to the **prod** Jenkins controller.
2. **Build** — Jenkins dispatches Nix builds to its dedicated remote builders
   (`hetz86-1`, `hetzarm`). [sbomnix](https://github.com/tiiuae/sbomnix)
   generates SBOMs and SLSA provenance on the controller, and build
   artifacts are signed via the [NetHSM](#nethsm-gateways).
3. **Test** — built images are deployed to on-prem test agents over the Nebula
   overlay. Each agent houses physical hardware devices and runs one Jenkins
   agent service per test device.
4. **Results** — test results flow back to Jenkins and build status is
   reported on the GitHub PR.

The **release** environment is ephemeral: it is fully re-provisioned with
`inv install-release` for each Ghaf release, giving it a clean state. It has
its own dedicated builders and test agents, and is the only environment
authorized to push to the `ghaf-release` binary cache. Because the cache
persists across re-installs, release builds can reuse earlier results and only
rebuild what has changed. The **dev** environment mirrors prod for CI and test
development. The **dbg** environment only trusts the upstream `cache.nixos.org`
substituter (no `ghaf-dev` or `ghaf-release`), which enables testing fully
clean builds from source.

Having a self-hosted CI solution alongside GitHub Actions ensures Ghaf
is not fully dependent on a third-party service for build and test
infrastructure.

### GitHub Actions

Pushes and PRs to Ghaf `main` also trigger a
[GitHub Actions workflow](https://github.com/tiiuae/ghaf/blob/main/.github/workflows/build.yml)
that compiles a matrix of build targets across x86_64 and aarch64. The workflow
uses `nix-fast-build --remote` over SSH to offload compilation to
`hetz86-builder` and `hetzarm` — the same shared builders available for
developer remote builds. This path verifies that targets build successfully but
does not run hardware tests. This path exists primarily because it integrates
naturally with the developer workflow — build status appears directly on PRs
and commits in GitHub without requiring access to Jenkins.

### Release artifact storage

During builds, Jenkins stores artifacts (disk images, SLSA provenance,
signatures, test results) locally under `/var/lib/jenkins/artifacts/` on the
controller. For releases, the `ghaf-release-publish` pipeline verifies all
signatures, packages the artifacts into tarballs, and uploads them to Hetzner
Object Storage (an S3-compatible service, bucket `ghaf-artifacts`) using
minio-client. The [ghaf-archive](https://github.com/tiiuae/ghaf-archive) web
application provides a browsable frontend to the archived releases.

### Repository CI (ghaf-infra)

The ghaf-infra repository has its own GitHub Actions workflows
(`.github/workflows/`) for quality gates and security scanning.

**PR and push checks:**

- `check.yml` — runs `nix flake check` on PRs and pushes to main
  (fast syntax and lint gate).
- `test-ghaf-infra.yml` — builds all NixOS configurations for x86_64 and
  aarch64 using remote builders.
- `authorize.yml` — reusable authorization workflow. PRs from `tiiuae` org
  members are auto-approved; external PRs require manual approval before
  CI runs.
- `warn-on-workflow-changes.yml` — intentionally fails if `authorize.yml`
  or `test-ghaf-infra.yml` are modified in a PR, since those changes only
  take effect after merge.

**Security scanning:**

- `actions-security-analysis.yml` — runs [zizmor](https://woodruffw.github.io/zizmor/)
  to audit workflow files for security issues.
- `codeql.yml` — CodeQL static analysis on Python code.
- `dependency-review.yml` — blocks PRs that introduce known-vulnerable
  dependencies.
- `scorecards.yml` — [OSSF Scorecard](https://securityscorecards.dev/)
  supply chain security analysis.

**Automation:**

- `update-robot-framework.yml` — daily automated PR to bump the
  robot-framework flake input.
- `update-flake-inputs.yml` — weekly automated PR to update all flake inputs
  and Jenkins plugin manifests.
- Dependabot (`.github/dependabot.yml`) keeps GitHub Actions and Go module
  dependencies up to date.

## Network Architecture

The infrastructure spans three network tiers:

| Tier | Subnet | Purpose |
|---|---|---|
| Public internet | Public IPs | Jenkins UIs, Grafana, web services (ACME TLS via Caddy) |
| Hetzner internal | `10.0.0.0/24` | Cloud-to-cloud communication between Hetzner hosts |
| Nebula overlay | `10.42.42.0/24` | Encrypted tunnel connecting Hetzner, Tampere office, and UAE site |

**Nebula** is a peer-to-peer overlay — traffic flows directly between hosts,
not through the lighthouse. The lighthouse (`ghaf-lighthouse`) is only a
discovery node. It also serves as a DNS server for the `sumu.vedenemo.dev`
subdomain, resolving Nebula addresses within the overlay.

Not every host joins the Nebula network. Only hosts that need to communicate
with on-prem or cross-site resources have Nebula IPs: the Jenkins controllers
(`hetzci-prod`, `hetzci-dev`, `hetzci-release`), `ghaf-monitoring`,
`ghaf-lighthouse`, all test agents, and the NetHSM gateways. Hosts that only
operate within Hetzner — such as the remote builders (`hetz86-1`,
`hetz86-builder`, `hetzarm`, etc.) — rely on public IPs or the Hetzner
internal network and have no Nebula connectivity. This is why builders cannot
directly reach on-prem hardware; only the Jenkins controllers bridge that gap.

See [Nebula overlay network](./nebula.md) for certificate management and
configuration details.

## Authentication

All user-facing services authenticate through a central OIDC provider:

- **ghaf-auth** runs [Dex](https://dexidp.io/) with a GitHub connector backed
  by `tiiuae` organization membership.
- Jenkins controllers sit behind [OAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/),
  which validates tokens with ghaf-auth before forwarding requests to Jenkins.
- Grafana and the OCI registry also authenticate via GitHub / OIDC.

See [Jenkins authentication](./jenkins-authentication.md) for the full
auth flow and secret generation.

## Secrets Management

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix) and
encrypted with [age](https://age-encryption.org/) keys:

- Each host has a `secrets.yaml` containing its encrypted secrets.
- `.sops.yaml` at the repo root maps secrets to the age keys (admin users +
  host keys) that can decrypt them.
- On boot (or `nixos-rebuild switch`), sops-nix automatically decrypts secrets
  and places them at configured file paths.
- Each host's private SSH key is stored as a sops secret and automatically
  deployed on [host installation](./tasks.md#install). The age key used for
  decryption is derived from this SSH host key.
- `secrets.yaml` files are created and edited with the `sops` CLI tool.
- Admin key changes require running `inv update-sops-files` to re-encrypt all
  secrets with the updated key set.

Plaintext secrets are **never** committed to the repository. The secrets
configuration was originally adopted from the
[nix-community infra](https://github.com/nix-community/infra) project.

## Monitoring and Logging

`ghaf-monitoring` runs Prometheus, Grafana, and Loki on a dedicated Hetzner
volume.

**Metrics collection** (Prometheus scrape jobs):

| Job | Transport | Hosts |
|---|---|---|
| `hetzner-cloud` | Hetzner internal network (direct) | Cloud VMs with `internal_ip` |
| `hetzner-robot` | SSH proxy (`sshified`) | Dedicated servers without internal network access |
| `office` / `relay-board` / `nethsm` | Nebula overlay | On-prem test agents, NetHSM gateway |

**Logging** — hosts run Grafana Alloy agents that push systemd journal logs to
Loki on `ghaf-monitoring`. Alerting is configured to notify a Slack channel.

**`ghaf-log`** (ghaflogs.vedenemo.dev) is a separate Grafana + Loki instance
for Ghaf device logs, independent from the infrastructure monitoring on
`ghaf-monitoring`. It exposes a basic-auth Loki API at
`loki.ghaflogs.vedenemo.dev` for external log producers.

All Grafana dashboards and alerts are provisioned declaratively through Nix;
manual edits in the Grafana UI are not persisted.

See [Monitoring](./monitoring.md) for development and debugging details.

## Deployment

| Method | Use case |
|---|---|
| [`deploy-rs`](./deploy-rs.md) | Push configuration changes to running hosts (with automatic rollback) |
| [`nixos-anywhere`](https://github.com/nix-community/nixos-anywhere) + [`disko`](https://github.com/nix-community/disko) | Initial provisioning — partitions disks and installs NixOS |
| [`invoke` tasks](./tasks.md) | Operational workflows (`inv install`, `inv reboot`, `inv update-sops-files`, `inv install-release`, etc.) |

## Cross-References

- [Deployment tasks](./tasks.md) — install, reboot, and other invoke tasks
- [Deploying with deploy-rs](./deploy-rs.md) — deploying configuration changes
- [Monitoring](./monitoring.md) — Grafana, Prometheus, and Loki setup
- [Nebula overlay network](./nebula.md) — overlay network and certificate management
- [NetHSM hardware signing](./nethsm.md) — PKCS#11 proxy and signing operations
- [Jenkins authentication](./jenkins-authentication.md) — OIDC auth flow
- [Jenkins test agents](./jenkins-testagents.md) — on-prem test agent setup
- [Jenkins CI development](../hosts/hetzci/README.md) — CI environments and pipeline overview
- [`hosts/machines.nix`](../hosts/machines.nix) — host inventory (IPs, keys, Nebula addresses)
